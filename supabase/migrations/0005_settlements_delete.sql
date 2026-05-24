-------------------------------------------------------------------------------
-- Allow a settlement to be undone by either party, and keep the activity
-- feed honest about it.
--
-- Settlements were INSERT-only in 0001. In practice users typo amounts or
-- log payments twice, so we need a recovery path. Both `from_profile` and
-- `to_profile` can delete — the symmetric INSERT policy already lets either
-- side log, so mirroring that for DELETE matches the mental model.
--
-- We also delete the matching `settle` activity row in an AFTER DELETE
-- trigger so the feed doesn't keep claiming "Aman paid Riya 500" after the
-- row is gone. Trigger is SECURITY DEFINER because activity_events has no
-- DELETE policy and we don't want to add one (writes-only from clients;
-- cleanups only from triggers).
-------------------------------------------------------------------------------
create policy "from_to can delete settlements" on public.settlements
  for delete using (
    from_profile = auth.uid() or to_profile = auth.uid()
  );

create or replace function public.purge_settlement_activity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.activity_events
  where kind = 'settle' and target_id = old.id;
  return old;
end
$$;

drop trigger if exists on_settlement_delete on public.settlements;
create trigger on_settlement_delete
  after delete on public.settlements
  for each row execute function public.purge_settlement_activity();
