-- 0010_cascade_groups_created_by.sql
--
-- groups.created_by was referencing profiles(id) without ON DELETE CASCADE.
-- Deleting a user cascaded auth.users → profiles but then hit this FK and
-- aborted. Re-create the constraint with CASCADE so deleting a user also
-- deletes the groups they created (which in turn cascades to expenses,
-- shares, settlements, activity, and group_members via the existing 0001
-- CASCADE chains).

alter table public.groups
  drop constraint groups_created_by_fkey,
  add constraint groups_created_by_fkey
    foreign key (created_by)
    references public.profiles(id)
    on delete cascade;
