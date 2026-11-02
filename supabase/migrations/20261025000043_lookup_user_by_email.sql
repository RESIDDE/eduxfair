-- 20261025000043_lookup_user_by_email.sql
create or replace function public.lookup_user_by_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id from auth.users where lower(trim(email)) = lower(trim(p_email));
  return v_id;
end;
$$;

revoke all on function public.lookup_user_by_email(text) from public, anon, authenticated;
grant execute on function public.lookup_user_by_email(text) to service_role;
