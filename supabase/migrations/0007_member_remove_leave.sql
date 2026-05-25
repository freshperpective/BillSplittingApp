-------------------------------------------------------------------------------
-- Allow members to leave a group and owners to remove members.
--
-- The DELETE policy is intentionally narrow: only rows with role='member'
-- can be deleted, and only when the caller is either an owner of that
-- group OR the member being removed. That gives us:
--   - owners can remove anyone except themselves
--   - members can self-leave
--   - owners cannot delete themselves out of a group (they delete the
--     group itself, via the existing flow gated by 0004)
--
-- Without this policy DELETE would 42501 — there was no DELETE policy on
-- group_members in 0001.
-------------------------------------------------------------------------------
create policy "remove or leave member" on public.group_members
  for delete using (
    role = 'member'
    and (
      -- Owner of this group can remove non-owners.
      exists (
        select 1 from public.group_members owner_check
        where owner_check.group_id = group_members.group_id
          and owner_check.profile_id = auth.uid()
          and owner_check.role = 'owner'
      )
      -- Or the row IS the caller (self-leave).
      or profile_id = auth.uid()
    )
  );

-------------------------------------------------------------------------------
-- Activity event for member removal / self-leave.
--
-- Mirrors the existing on_member_insert trigger. We re-use the
-- group.member.add kind would be confusing, so we add a new
-- kind 'group.member.remove'. The actor is the caller — for self-leave
-- that's the leaving member; for owner-removes it's the owner.
-------------------------------------------------------------------------------
create or replace function public.log_member_remove_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := coalesce(public._activity_actor(), old.profile_id);
begin
  insert into public.activity_events(group_id, actor, kind, target_id, payload)
  values (
    old.group_id,
    v_actor,
    'group.member.remove',
    old.profile_id,
    jsonb_build_object(
      'profile_id', old.profile_id,
      'self_leave', v_actor = old.profile_id
    )
  );
  return old;
end
$$;

drop trigger if exists on_member_delete on public.group_members;
create trigger on_member_delete
  after delete on public.group_members
  for each row execute function public.log_member_remove_activity();
