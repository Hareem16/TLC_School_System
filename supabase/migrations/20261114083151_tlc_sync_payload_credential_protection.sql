create or replace function public.tlc_sync_payload_is_safe(p_value jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_item record;
  v_key text;
begin
  if jsonb_typeof(p_value) = 'object' then
    for v_item in select key, value from jsonb_each(p_value)
    loop
      v_key := lower(v_item.key);
      if v_key = any(array[
        'password','password_hash','password_salt','salt','hash',
        'access_token','refresh_token','service_role','service_key',
        'secret_key','private_key','api_secret'
      ]) then
        return false;
      end if;
      if not public.tlc_sync_payload_is_safe(v_item.value) then
        return false;
      end if;
    end loop;
  elsif jsonb_typeof(p_value) = 'array' then
    for v_item in select value from jsonb_array_elements(p_value)
    loop
      if not public.tlc_sync_payload_is_safe(v_item.value) then
        return false;
      end if;
    end loop;
  end if;
  return true;
end;
$function$;

create or replace function public.tlc_sync_push(
  p_school_id uuid, p_device_id uuid, p_changes jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_device_ok boolean;
  v_change jsonb;
  v_change_id uuid;
  v_entity text;
  v_record_id text;
  v_operation text;
  v_payload jsonb;
  v_base_revision bigint;
  v_current_revision bigint;
  v_new_revision bigint;
  v_server_seq bigint;
  v_results jsonb := '[]'::jsonb;
  v_receipt public.school_sync_receipts%rowtype;
begin
  if v_user_id is null then raise exception 'Sign-in required'; end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array'
     or jsonb_array_length(p_changes) < 1 or jsonb_array_length(p_changes) > 100 then
    raise exception 'A batch must contain between 1 and 100 changes';
  end if;
  select m.role into v_role from public.school_memberships m
  where m.school_id=p_school_id and m.user_id=v_user_id and m.is_active=true;
  if v_role is null then raise exception 'Active school membership required'; end if;
  select exists(select 1 from public.registered_devices d
    where d.id=p_device_id and d.school_id=p_school_id
      and d.user_id=v_user_id and d.status='approved') into v_device_ok;
  if not v_device_ok then raise exception 'This device is not approved for this school'; end if;

  for v_change in select value from jsonb_array_elements(p_changes)
  loop
    v_change_id := nullif(v_change->>'client_change_id','')::uuid;
    v_entity := v_change->>'entity_type';
    v_record_id := v_change->>'record_id';
    v_operation := v_change->>'operation';
    v_payload := coalesce(v_change->'payload','{}'::jsonb);
    v_base_revision := coalesce(nullif(v_change->>'base_revision','')::bigint,0);
    if v_change_id is null or v_entity is null or v_record_id is null
       or length(v_record_id)=0 or length(v_record_id)>255
       or v_operation is null or v_operation not in ('insert','update','delete')
       or jsonb_typeof(v_payload)<>'object' then
      raise exception 'Invalid sync change format';
    end if;
    if octet_length(v_payload::text)>1048576 then
      raise exception 'A sync record cannot exceed 1 MiB';
    end if;
    if not public.tlc_sync_payload_is_safe(v_payload) then
      raise exception 'Sensitive credential or token fields are prohibited in sync payloads';
    end if;
    if not public.tlc_sync_entity_allowed(v_role,v_entity) then
      raise exception 'Role % is not permitted to sync entity %',v_role,v_entity;
    end if;
    if v_entity in ('fee_payments','fee_payment_reversals') and v_operation<>'insert' then
      raise exception 'Financial receipts and reversals cannot be updated or deleted';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(
      p_school_id::text || ':change:' || v_change_id::text,0));
    perform pg_advisory_xact_lock(hashtextextended(
      p_school_id::text || ':' || v_entity || ':' || v_record_id,0));
    select * into v_receipt from public.school_sync_receipts r
    where r.school_id=p_school_id and r.client_change_id=v_change_id;
    if found then
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'client_change_id',v_change_id,'status','already_applied',
        'revision',v_receipt.revision,'server_seq',v_receipt.server_seq));
      continue;
    end if;
    select r.revision into v_current_revision from public.school_sync_records r
    where r.school_id=p_school_id and r.entity_type=v_entity
      and r.record_id=v_record_id for update;
    if not found then v_current_revision:=0; end if;
    if v_current_revision<>v_base_revision then
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'client_change_id',v_change_id,'status','conflict',
        'current_revision',v_current_revision));
      continue;
    end if;
    v_new_revision:=v_current_revision+1;
    insert into public.school_sync_records(
      school_id,entity_type,record_id,payload,revision,is_deleted,
      last_change_id,changed_by,device_id,updated_at)
    values(p_school_id,v_entity,v_record_id,
      case when v_operation='delete' then '{}'::jsonb else v_payload end,
      v_new_revision,(v_operation='delete'),v_change_id,v_user_id,p_device_id,now())
    on conflict(school_id,entity_type,record_id) do update set
      payload=excluded.payload,revision=excluded.revision,is_deleted=excluded.is_deleted,
      last_change_id=excluded.last_change_id,changed_by=excluded.changed_by,
      device_id=excluded.device_id,updated_at=excluded.updated_at
    returning server_seq into v_server_seq;
    insert into public.school_sync_receipts(
      school_id,client_change_id,entity_type,record_id,revision,server_seq)
    values(p_school_id,v_change_id,v_entity,v_record_id,v_new_revision,v_server_seq);
    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'client_change_id',v_change_id,'status','applied',
      'revision',v_new_revision,'server_seq',v_server_seq));
  end loop;
  return jsonb_build_object('results',v_results);
end;
$function$;

revoke all on function public.tlc_sync_entity_allowed(text,text) from public,anon,authenticated;
revoke all on function public.tlc_sync_payload_is_safe(jsonb) from public,anon,authenticated;
grant execute on function public.tlc_sync_entity_allowed(text,text) to postgres;
grant execute on function public.tlc_sync_payload_is_safe(jsonb) to postgres;
revoke all on function public.tlc_sync_push(uuid,uuid,jsonb) from public,anon;
grant execute on function public.tlc_sync_push(uuid,uuid,jsonb) to authenticated;
