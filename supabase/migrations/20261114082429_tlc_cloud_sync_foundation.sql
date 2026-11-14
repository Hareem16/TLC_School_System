-- TLC School System cloud sync foundation.
-- Additive only: existing schools, memberships, devices and sync_events are preserved.

create table if not exists public.school_sync_records (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete restrict,
  entity_type text not null,
  record_id text not null,
  payload jsonb not null default '{}'::jsonb,
  revision bigint not null default 1 check (revision > 0),
  is_deleted boolean not null default false,
  last_change_id uuid not null,
  changed_by uuid not null references auth.users(id) on delete restrict,
  device_id uuid not null references public.registered_devices(id) on delete restrict,
  server_seq bigint generated always as identity unique,
  updated_at timestamptz not null default now(),
  constraint school_sync_records_entity_check check (
    entity_type = any (array[
      'school_profiles','students','staff','library_books','attendance',
      'fee_charges','fee_payments','fee_payment_allocations',
      'fee_payment_reversals','inventory_items','inventory_movements',
      'staff_salary_records','exams','exam_subjects','exam_results',
      'timetable_entries','exam_subject_teachers','exam_class_teachers',
      'exam_publications','complaints','class_subjects','school_notices',
      'ece_worksheets','admin_audit_logs'
    ])
  ),
  constraint school_sync_records_unique_record unique (school_id, entity_type, record_id),
  constraint school_sync_records_unique_change unique (school_id, last_change_id)
);

create index if not exists school_sync_records_pull_idx
  on public.school_sync_records (school_id, server_seq);

create table if not exists public.school_sync_receipts (
  school_id uuid not null references public.schools(id) on delete restrict,
  client_change_id uuid not null,
  entity_type text not null,
  record_id text not null,
  revision bigint not null,
  server_seq bigint not null,
  created_at timestamptz not null default now(),
  primary key (school_id, client_change_id)
);

alter table public.school_sync_records enable row level security;
alter table public.school_sync_receipts enable row level security;
revoke all on public.school_sync_records from anon, authenticated;
revoke all on public.school_sync_receipts from anon, authenticated;

create or replace function public.tlc_sync_entity_allowed(
  p_role text,
  p_entity_type text
)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select case
    when p_role in ('owner','admin','principal') then
      p_entity_type = any (array[
        'school_profiles','students','staff','library_books','attendance',
        'fee_charges','fee_payments','fee_payment_allocations',
        'fee_payment_reversals','inventory_items','inventory_movements',
        'staff_salary_records','exams','exam_subjects','exam_results',
        'timetable_entries','exam_subject_teachers','exam_class_teachers',
        'exam_publications','complaints','class_subjects','school_notices',
        'ece_worksheets','admin_audit_logs'
      ])
    when p_role = 'fdo' then
      p_entity_type = any (array[
        'fee_charges','fee_payments','fee_payment_allocations',
        'fee_payment_reversals','inventory_items','inventory_movements'
      ])
    else false
  end;
$function$;

create or replace function public.tlc_sync_push(
  p_school_id uuid,
  p_device_id uuid,
  p_changes jsonb
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
     or jsonb_array_length(p_changes) < 1
     or jsonb_array_length(p_changes) > 100 then
    raise exception 'A batch must contain between 1 and 100 changes';
  end if;

  select m.role into v_role
  from public.school_memberships m
  where m.school_id = p_school_id and m.user_id = v_user_id and m.is_active = true;
  if v_role is null then raise exception 'Active school membership required'; end if;

  select exists (
    select 1 from public.registered_devices d
    where d.id = p_device_id and d.school_id = p_school_id
      and d.user_id = v_user_id and d.status = 'approved'
  ) into v_device_ok;
  if not v_device_ok then raise exception 'This device is not approved for this school'; end if;

  for v_change in select value from jsonb_array_elements(p_changes)
  loop
    v_change_id := (v_change->>'client_change_id')::uuid;
    v_entity := v_change->>'entity_type';
    v_record_id := v_change->>'record_id';
    v_operation := v_change->>'operation';
    v_payload := coalesce(v_change->'payload', '{}'::jsonb);
    v_base_revision := coalesce((v_change->>'base_revision')::bigint, 0);

    if v_change_id is null or v_entity is null or v_record_id is null
       or length(v_record_id) = 0 or length(v_record_id) > 255
       or v_operation not in ('insert','update','delete')
       or jsonb_typeof(v_payload) <> 'object' then
      raise exception 'Invalid sync change format';
    end if;

    if not public.tlc_sync_entity_allowed(v_role, v_entity) then
      raise exception 'Role % is not permitted to sync entity %', v_role, v_entity;
    end if;

    select * into v_receipt from public.school_sync_receipts r
    where r.school_id = p_school_id and r.client_change_id = v_change_id;
    if found then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'client_change_id', v_change_id, 'status', 'already_applied',
        'revision', v_receipt.revision, 'server_seq', v_receipt.server_seq
      ));
      continue;
    end if;

    select r.revision into v_current_revision
    from public.school_sync_records r
    where r.school_id = p_school_id and r.entity_type = v_entity
      and r.record_id = v_record_id for update;
    if not found then v_current_revision := 0; end if;

    if v_current_revision <> v_base_revision then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'client_change_id', v_change_id, 'status', 'conflict',
        'current_revision', v_current_revision
      ));
      continue;
    end if;

    v_new_revision := v_current_revision + 1;
    insert into public.school_sync_records (
      school_id, entity_type, record_id, payload, revision, is_deleted,
      last_change_id, changed_by, device_id, updated_at
    )
    values (
      p_school_id, v_entity, v_record_id,
      case when v_operation = 'delete' then '{}'::jsonb else v_payload end,
      v_new_revision, (v_operation = 'delete'), v_change_id, v_user_id, p_device_id, now()
    )
    on conflict (school_id, entity_type, record_id) do update set
      payload = excluded.payload, revision = excluded.revision,
      is_deleted = excluded.is_deleted, last_change_id = excluded.last_change_id,
      changed_by = excluded.changed_by, device_id = excluded.device_id,
      updated_at = excluded.updated_at
    returning server_seq into v_server_seq;

    insert into public.school_sync_receipts (
      school_id, client_change_id, entity_type, record_id, revision, server_seq
    ) values (p_school_id, v_change_id, v_entity, v_record_id, v_new_revision, v_server_seq);

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'client_change_id', v_change_id, 'status', 'applied',
      'revision', v_new_revision, 'server_seq', v_server_seq
    ));
  end loop;
  return jsonb_build_object('results', v_results);
end;
$function$;

create or replace function public.tlc_sync_pull(
  p_school_id uuid,
  p_device_id uuid,
  p_after_seq bigint default 0,
  p_limit integer default 200
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
  v_records jsonb;
  v_next_cursor bigint;
begin
  if v_user_id is null then raise exception 'Sign-in required'; end if;
  if p_limit < 1 or p_limit > 500 then raise exception 'Pull limit must be between 1 and 500'; end if;

  select m.role into v_role from public.school_memberships m
  where m.school_id = p_school_id and m.user_id = v_user_id and m.is_active = true;
  if v_role is null then raise exception 'Active school membership required'; end if;

  select exists (
    select 1 from public.registered_devices d
    where d.id = p_device_id and d.school_id = p_school_id
      and d.user_id = v_user_id and d.status = 'approved'
  ) into v_device_ok;
  if not v_device_ok then raise exception 'This device is not approved for this school'; end if;

  if v_role not in ('owner','admin','principal','fdo') then
    raise exception 'Cloud sync for this role requires approved class/student scopes';
  end if;

  select
    coalesce(jsonb_agg(to_jsonb(page_row) - 'server_seq' order by page_row.server_seq), '[]'::jsonb),
    coalesce(max(page_row.server_seq), coalesce(p_after_seq, 0))
  into v_records, v_next_cursor
  from (
    select r.server_seq, r.entity_type, r.record_id, r.payload,
      r.revision, r.is_deleted, r.updated_at
    from public.school_sync_records r
    where r.school_id = p_school_id and r.server_seq > coalesce(p_after_seq, 0)
      and public.tlc_sync_entity_allowed(v_role, r.entity_type)
    order by r.server_seq limit p_limit
  ) page_row;

  return jsonb_build_object('records', v_records, 'next_cursor', v_next_cursor);
end;
$function$;

revoke all on function public.tlc_sync_entity_allowed(text,text) from public, anon;
revoke all on function public.tlc_sync_push(uuid,uuid,jsonb) from public, anon;
revoke all on function public.tlc_sync_pull(uuid,uuid,bigint,integer) from public, anon;
grant execute on function public.tlc_sync_entity_allowed(text,text) to authenticated;
grant execute on function public.tlc_sync_push(uuid,uuid,jsonb) to authenticated;
grant execute on function public.tlc_sync_pull(uuid,uuid,bigint,integer) to authenticated;

revoke all on function public.is_school_admin(uuid) from public, anon;
revoke all on function public.is_school_member(uuid) from public, anon;
revoke all on function public.create_school(text,text) from public, anon;
grant execute on function public.is_school_admin(uuid) to authenticated;
grant execute on function public.is_school_member(uuid) to authenticated;
grant execute on function public.create_school(text,text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('tlc-school-backups','tlc-school-backups',false,524288000,
  array['application/octet-stream','application/zip'])
on conflict (id) do nothing;

do $policies$
begin
  if not exists (select 1 from pg_policies where schemaname='storage'
    and tablename='objects' and policyname='tlc_backup_admin_upload') then
    create policy tlc_backup_admin_upload on storage.objects
    for insert to authenticated with check (
      bucket_id='tlc-school-backups'
      and array_length(storage.foldername(name),1)>=2
      and (storage.foldername(name))[2]=auth.uid()::text
      and public.is_school_admin(((storage.foldername(name))[1])::uuid)
    );
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage'
    and tablename='objects' and policyname='tlc_backup_admin_read') then
    create policy tlc_backup_admin_read on storage.objects
    for select to authenticated using (
      bucket_id='tlc-school-backups'
      and array_length(storage.foldername(name),1)>=2
      and (storage.foldername(name))[2]=auth.uid()::text
      and public.is_school_admin(((storage.foldername(name))[1])::uuid)
    );
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage'
    and tablename='objects' and policyname='tlc_backup_admin_update') then
    create policy tlc_backup_admin_update on storage.objects
    for update to authenticated using (
      bucket_id='tlc-school-backups'
      and array_length(storage.foldername(name),1)>=2
      and (storage.foldername(name))[2]=auth.uid()::text
      and public.is_school_admin(((storage.foldername(name))[1])::uuid)
    ) with check (
      bucket_id='tlc-school-backups'
      and array_length(storage.foldername(name),1)>=2
      and (storage.foldername(name))[2]=auth.uid()::text
      and public.is_school_admin(((storage.foldername(name))[1])::uuid)
    );
  end if;
end;
$policies$;
