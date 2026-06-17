-- 0012_group_invites.sql
--
-- Adds a group_invites table so members can generate short-lived invite
-- codes and share them with people who don't yet have the app.
--
-- Flow:
--   1. Member calls createInvite(groupId) → gets an 8-char code back.
--   2. They share the code (or the GitHub Pages join link) via any channel.
--   3. Recipient installs the app, signs in, enters the code.
--   4. App calls claim_group_invite(code) SECURITY DEFINER RPC → validates
--      expiry + single-use, inserts into group_members, marks invite used.

create table if not exists public.group_invites (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups(id) on delete cascade,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  -- 8-char uppercase alphanumeric code derived from a random UUID.
  code        text not null unique
                default upper(substr(replace(gen_random_uuid()::text,'-',''), 1, 8)),
  expires_at  timestamptz not null default now() + interval '7 days',
  used_by     uuid references public.profiles(id) on delete set null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

alter table public.group_invites enable row level security;

-- Any group member can create an invite for their group.
create policy "members can create invites" on public.group_invites
  for insert with check (
    public.is_group_member(group_id) and created_by = auth.uid()
  );

-- Any authenticated user can look up an invite by code (needed to join).
create policy "authenticated can read invites" on public.group_invites
  for select using (auth.uid() is not null);

-- SECURITY DEFINER so the function can write group_members regardless of
-- who calls it — the code + expiry check is the auth gate.
create or replace function public.claim_group_invite(invite_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.group_invites;
begin
  select * into v_invite
  from public.group_invites
  where upper(code) = upper(invite_code)
    and expires_at > now()
    and used_by is null;

  if not found then
    raise exception 'Invalid or expired invite code.';
  end if;

  if exists (
    select 1 from public.group_members
    where group_id = v_invite.group_id and profile_id = auth.uid()
  ) then
    raise exception 'You are already a member of this group.';
  end if;

  insert into public.group_members (group_id, profile_id, role)
  values (v_invite.group_id, auth.uid(), 'member')
  on conflict do nothing;

  update public.group_invites
  set used_by = auth.uid(), used_at = now()
  where id = v_invite.id;

  return json_build_object('group_id', v_invite.group_id);
end$$;
