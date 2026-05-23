-- Tabby — RPC for looking up a profile by email so an owner can add a
-- member to their group without being able to read the full profiles table.
--
-- Run via: supabase db push  (or paste into the SQL editor of your project)

create or replace function public.find_profile_by_email(p_email text)
returns table (id uuid, display_name text)
language sql
security definer
stable
set search_path = public
as $$
  select p.id, p.display_name
  from auth.users u
  join public.profiles p on p.id = u.id
  where u.email = lower(trim(p_email))
  limit 1;
$$;

-- Only authenticated users can call this. Anon access would let anyone
-- enumerate which emails have accounts.
revoke execute on function public.find_profile_by_email(text) from public;
grant execute on function public.find_profile_by_email(text) to authenticated;
