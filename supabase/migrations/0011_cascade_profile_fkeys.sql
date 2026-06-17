-- 0011_cascade_profile_fkeys.sql
--
-- Several FKs that reference profiles(id) were created without ON DELETE
-- CASCADE in 0001, so deleting a user cascaded auth.users → profiles but
-- then aborted on whichever child table was checked first.
--
-- Fix: re-create every profiles(id) FK with ON DELETE CASCADE so that
-- deleting a user cleanly removes all their rows across every table.
-- groups.created_by was already patched in 0010; the rest are done here.

-- activity_events.actor
alter table public.activity_events
  drop constraint activity_events_actor_fkey,
  add constraint activity_events_actor_fkey
    foreign key (actor)
    references public.profiles(id)
    on delete cascade;

-- expenses.created_by
alter table public.expenses
  drop constraint expenses_created_by_fkey,
  add constraint expenses_created_by_fkey
    foreign key (created_by)
    references public.profiles(id)
    on delete cascade;

-- expense_shares.profile_id
alter table public.expense_shares
  drop constraint expense_shares_profile_id_fkey,
  add constraint expense_shares_profile_id_fkey
    foreign key (profile_id)
    references public.profiles(id)
    on delete cascade;

-- settlements.from_profile
alter table public.settlements
  drop constraint settlements_from_profile_fkey,
  add constraint settlements_from_profile_fkey
    foreign key (from_profile)
    references public.profiles(id)
    on delete cascade;

-- settlements.to_profile
alter table public.settlements
  drop constraint settlements_to_profile_fkey,
  add constraint settlements_to_profile_fkey
    foreign key (to_profile)
    references public.profiles(id)
    on delete cascade;
