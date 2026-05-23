-------------------------------------------------------------------------------
-- Activity event triggers
--
-- Why server-side: the activity feed is the source of truth for "what
-- happened". Putting the writes in DB triggers means we can never forget to
-- log an event from a new client codepath (and we don't have to round-trip
-- two writes per mutation). All trigger functions are SECURITY DEFINER so
-- they bypass the `actor = auth.uid()` INSERT policy on activity_events
-- — auth.uid() is still readable here, but RLS isn't checked on the
-- definer's tables.
--
-- Payload shape: kept intentionally minimal (IDs + a few structured fields).
-- The repository hydrates actor/peer names + group names in a single batch
-- read on load, so renames propagate to the feed immediately.
-------------------------------------------------------------------------------

-- Resolve the actor for an activity row. Falls back to NULL when running
-- outside a PostgREST session (e.g., during the backfill at the bottom of
-- this file) — callers COALESCE this with a sensible default (created_by,
-- from_profile, etc.).
create or replace function public._activity_actor()
returns uuid language sql stable as $$
  select auth.uid()
$$;

-------------------------------------------------------------------------------
-- expenses: add / edit / soft-delete
-------------------------------------------------------------------------------
create or replace function public.log_expense_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid;
  v_kind text;
  v_payload jsonb;
begin
  if tg_op = 'INSERT' then
    v_actor := coalesce(public._activity_actor(), new.created_by);
    v_kind := 'expense.add';
    v_payload := jsonb_build_object(
      'description', new.description,
      'amount',      new.amount::text,
      'currency',    new.currency
    );
    insert into public.activity_events(group_id, actor, kind, target_id, payload)
    values (new.group_id, v_actor, v_kind, new.id, v_payload);
    return new;

  elsif tg_op = 'UPDATE' then
    v_actor := coalesce(public._activity_actor(), new.created_by);

    -- Soft-delete: deleted_at flipped from NULL to a value.
    if old.deleted_at is null and new.deleted_at is not null then
      v_kind := 'expense.delete';
      v_payload := jsonb_build_object(
        'description', new.description,
        'amount',      new.amount::text,
        'currency',    new.currency
      );

    -- A real edit: description or amount changed (ignore no-op updates so
    -- the feed doesn't fill with phantom rows from internal touches).
    elsif new.description is distinct from old.description
       or new.amount      is distinct from old.amount then
      v_kind := 'expense.edit';
      v_payload := jsonb_build_object(
        'description',     new.description,
        'amount',          new.amount::text,
        'currency',        new.currency,
        'old_description', old.description,
        'old_amount',      old.amount::text
      );

    else
      return new; -- nothing user-visible changed
    end if;

    insert into public.activity_events(group_id, actor, kind, target_id, payload)
    values (new.group_id, v_actor, v_kind, new.id, v_payload);
    return new;
  end if;

  return new;
end
$$;

drop trigger if exists on_expense_change on public.expenses;
create trigger on_expense_change
  after insert or update on public.expenses
  for each row execute function public.log_expense_activity();

-------------------------------------------------------------------------------
-- settlements: settle
-------------------------------------------------------------------------------
create or replace function public.log_settlement_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := coalesce(public._activity_actor(), new.from_profile);
begin
  insert into public.activity_events(group_id, actor, kind, target_id, payload)
  values (
    new.group_id, v_actor, 'settle', new.id,
    jsonb_build_object(
      'amount',       new.amount::text,
      'currency',     new.currency,
      'from_profile', new.from_profile,
      'to_profile',   new.to_profile
    )
  );
  return new;
end
$$;

drop trigger if exists on_settlement_insert on public.settlements;
create trigger on_settlement_insert
  after insert on public.settlements
  for each row execute function public.log_settlement_activity();

-------------------------------------------------------------------------------
-- groups: group.create
-------------------------------------------------------------------------------
create or replace function public.log_group_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := coalesce(public._activity_actor(), new.created_by);
begin
  insert into public.activity_events(group_id, actor, kind, target_id, payload)
  values (
    new.id, v_actor, 'group.create', new.id,
    jsonb_build_object('name', new.name, 'emoji', new.emoji)
  );
  return new;
end
$$;

drop trigger if exists on_group_insert on public.groups;
create trigger on_group_insert
  after insert on public.groups
  for each row execute function public.log_group_activity();

-------------------------------------------------------------------------------
-- group_members: group.member.add
--
-- The existing on_group_created trigger auto-inserts the creator as 'owner'.
-- We skip that row here so the feed doesn't double-log "X created the group"
-- and "X joined the group" on the same event. Member-adds by an owner come
-- through with role = 'member' and ARE logged.
-------------------------------------------------------------------------------
create or replace function public.log_member_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := coalesce(public._activity_actor(), new.profile_id);
begin
  if new.role = 'owner' then
    return new;
  end if;
  insert into public.activity_events(group_id, actor, kind, target_id, payload)
  values (
    new.group_id, v_actor, 'group.member.add', new.profile_id,
    jsonb_build_object('profile_id', new.profile_id)
  );
  return new;
end
$$;

drop trigger if exists on_member_insert on public.group_members;
create trigger on_member_insert
  after insert on public.group_members
  for each row execute function public.log_member_activity();

-------------------------------------------------------------------------------
-- One-shot backfill of pre-existing rows. Idempotent — keyed by
-- (kind, target_id) so re-running this migration is a no-op.
-------------------------------------------------------------------------------
insert into public.activity_events(group_id, actor, kind, target_id, payload, created_at)
select g.id, g.created_by, 'group.create', g.id,
       jsonb_build_object('name', g.name, 'emoji', g.emoji), g.created_at
from public.groups g
where not exists (
  select 1 from public.activity_events ae
  where ae.kind = 'group.create' and ae.target_id = g.id
);

insert into public.activity_events(group_id, actor, kind, target_id, payload, created_at)
select e.group_id, e.created_by, 'expense.add', e.id,
       jsonb_build_object(
         'description', e.description,
         'amount',      e.amount::text,
         'currency',    e.currency
       ), e.created_at
from public.expenses e
where e.deleted_at is null
  and not exists (
    select 1 from public.activity_events ae
    where ae.kind = 'expense.add' and ae.target_id = e.id
  );

insert into public.activity_events(group_id, actor, kind, target_id, payload, created_at)
select s.group_id, s.from_profile, 'settle', s.id,
       jsonb_build_object(
         'amount',       s.amount::text,
         'currency',     s.currency,
         'from_profile', s.from_profile,
         'to_profile',   s.to_profile
       ), s.created_at
from public.settlements s
where not exists (
  select 1 from public.activity_events ae
  where ae.kind = 'settle' and ae.target_id = s.id
);

insert into public.activity_events(group_id, actor, kind, target_id, payload, created_at)
select gm.group_id, gm.profile_id, 'group.member.add', gm.profile_id,
       jsonb_build_object('profile_id', gm.profile_id), gm.joined_at
from public.group_members gm
where gm.role = 'member'
  and not exists (
    select 1 from public.activity_events ae
    where ae.kind = 'group.member.add'
      and ae.target_id = gm.profile_id
      and ae.group_id = gm.group_id
  );
