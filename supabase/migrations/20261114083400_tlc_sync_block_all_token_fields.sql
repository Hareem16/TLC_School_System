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
        'access_token','refresh_token','token','jwt','bearer',
        'credential','credentials','service_role','service_key',
        'secret','secret_key','private_key','api_secret'
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

revoke all on function public.tlc_sync_payload_is_safe(jsonb) from public, anon, authenticated;
