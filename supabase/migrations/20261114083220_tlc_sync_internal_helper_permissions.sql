revoke all on function public.tlc_sync_entity_allowed(text,text) from public, anon, authenticated;
revoke all on function public.tlc_sync_payload_is_safe(jsonb) from public, anon, authenticated;
grant execute on function public.tlc_sync_entity_allowed(text,text) to postgres;
grant execute on function public.tlc_sync_payload_is_safe(jsonb) to postgres;
