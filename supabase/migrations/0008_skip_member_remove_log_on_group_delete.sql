-------------------------------------------------------------------------------
-- Skip the group.member.remove activity write when the parent group is
-- already gone.
--
-- The trigger from 0007 fires AFTER DELETE on group_members. That's the
-- right hook for a regular "remove this member" or "leave the group"
-- action — but when the *group itself* is being deleted, the cascade
-- tears down every group_members row first and fires this trigger for
-- each one. By the time the trigger runs, the parent group is no longer
-- in `public.groups`, so the INSERT into `activity_events` (whose
-- group_id has `references public.groups(id)`) hits a 23503 foreign-key
-- violation and rolls back the entire group delete.
--
-- The fix: guard the insert with a quick existence check. If the group
-- has already gone, skip logging — the activity_events rows that belonged
-- to that group are about to be cascade-deleted anyway, so emitting
-- "X removed Y" mid-teardown would be noise.
-------------------------------------------------------------------------------
create or replace function public.log_member_remove_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := coalesce(public._activity_actor(), old.profile_id);
begin
  -- Cascade-from-group-delete guard: when the parent group is already
  -- being torn down, the FK target for activity_events.group_id is
  -- gone and INSERT would 23503.
  if not exists (select 1 from public.groups where id = old.group_id) then
    return old;
  end if;

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
