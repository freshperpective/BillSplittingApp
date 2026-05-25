-------------------------------------------------------------------------------
-- Expense receipts: private Storage bucket + metadata table.
--
-- Design choices:
--   - Private bucket (public = false). All access is via short-lived signed
--     URLs generated server-side — never a public permanent link.
--   - Path structure: {expense_id}/{uuid}.{ext}. Embedding the expense_id in
--     the path lets Storage RLS policies verify group membership with a single
--     join, without needing to look up the metadata table.
--   - Metadata table `expense_receipts` is the source of truth for which
--     objects belong to which expense.  The Storage object itself carries no
--     extra metadata — the path is the link.
--   - Hard limit of 5 receipts per expense is enforced in the application
--     layer (ReceiptsRepository.upload); no DB constraint needed.
--   - Cascade: when an expense is soft-deleted or hard-deleted, the metadata
--     rows are CASCADE-deleted, but the Storage objects are NOT automatically
--     removed (Supabase Storage doesn't support FK cascades to objects).
--     A periodic Edge Function can sweep orphaned objects; for v1 they are
--     benign (private, inaccessible).
--
-- Run order: after 0008.
-------------------------------------------------------------------------------

-- Storage bucket -------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values (
  'receipts',
  'receipts',
  false,      -- private: served only via signed URLs
  5242880     -- 5 MB per file; enforced by Supabase before RLS is evaluated
)
on conflict (id) do nothing;

-- Storage object RLS ---------------------------------------------------------
-- All three policies key on `bucket_id = 'receipts'` to scope them tightly.

-- Group members may download receipt objects.
-- We extract the expense_id from the first path segment (split_part) and
-- confirm the caller is a member of that expense's group.
create policy "group members read receipts"
  on storage.objects for select
  using (
    bucket_id = 'receipts'
    and exists (
      select 1
      from public.expenses e
      join public.group_members gm on gm.group_id = e.group_id
      where e.id::text = split_part(name, '/', 1)
        and gm.profile_id = auth.uid()
    )
  );

-- Group members may upload receipt objects (the metadata insert is a separate
-- step handled by the application after the upload succeeds).
create policy "group members upload receipts"
  on storage.objects for insert
  with check (
    bucket_id = 'receipts'
    and exists (
      select 1
      from public.expenses e
      join public.group_members gm on gm.group_id = e.group_id
      where e.id::text = split_part(name, '/', 1)
        and gm.profile_id = auth.uid()
    )
  );

-- Only the uploader (identified via the metadata row) may delete the object.
-- This keeps delete permission consistent with the metadata RLS below.
create policy "creator deletes receipt object"
  on storage.objects for delete
  using (
    bucket_id = 'receipts'
    and exists (
      select 1 from public.expense_receipts er
      where er.storage_path = name
        and er.created_by = auth.uid()
    )
  );

-- Receipt metadata table -----------------------------------------------------

create table public.expense_receipts (
  id           uuid        primary key default gen_random_uuid(),
  expense_id   uuid        not null references public.expenses(id) on delete cascade,
  storage_path text        not null unique,
  created_by   uuid        not null references public.profiles(id),
  created_at   timestamptz not null default now()
);

alter table public.expense_receipts enable row level security;

-- Group members may read receipt metadata for expenses in their groups.
create policy "members read expense receipts"
  on public.expense_receipts for select
  using (
    exists (
      select 1
      from public.expenses e
      join public.group_members gm on gm.group_id = e.group_id
      where e.id = expense_receipts.expense_id
        and gm.profile_id = auth.uid()
    )
  );

-- Group members may insert receipt metadata (created_by must equal auth.uid).
create policy "members insert expense receipts"
  on public.expense_receipts for insert
  with check (
    created_by = auth.uid()
    and exists (
      select 1
      from public.expenses e
      join public.group_members gm on gm.group_id = e.group_id
      where e.id = expense_receipts.expense_id
        and gm.profile_id = auth.uid()
    )
  );

-- Only the uploader may delete their own receipt metadata row.
create policy "creator deletes expense receipts"
  on public.expense_receipts for delete
  using (created_by = auth.uid());
