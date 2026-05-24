-------------------------------------------------------------------------------
-- Allow owners to delete a group.
--
-- 0001 set up CASCADE on every child table (group_members, expenses,
-- expense_shares via expenses, settlements, activity_events), so a DELETE
-- on `groups` nukes everything attached to it in one shot. The missing
-- piece was the RLS policy: by default, no policy = no one can delete.
--
-- Membership of role 'owner' is the gate, mirroring the existing UPDATE
-- policy on groups. Archive (`archived_at`) reuses that UPDATE policy
-- — no extra DDL needed there.
-------------------------------------------------------------------------------
create policy "owners can delete groups" on public.groups
  for delete using (
    exists (
      select 1 from public.group_members
      where group_id = groups.id
        and profile_id = auth.uid()
        and role = 'owner'
    )
  );
