-- Tabby — initial schema
-- Run via: supabase db push  (or paste into the SQL editor of your project)

create extension if not exists "pgcrypto";

-------------------------------------------------------------------------------
-- profiles : 1:1 with auth.users
-------------------------------------------------------------------------------
create table if not exists public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  display_name      text not null default '',
  avatar_url        text,
  default_currency  text not null default 'INR',
  created_at        timestamptz not null default now()
);

-- Auto-create a profile row when a new auth user appears.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, default_currency)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)), 'INR')
  on conflict (id) do nothing;
  return new;
end$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-------------------------------------------------------------------------------
-- groups + membership
-------------------------------------------------------------------------------
create table if not exists public.groups (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  emoji             text not null default '💸',
  default_currency  text not null default 'INR',
  created_by        uuid not null references public.profiles(id),
  archived_at       timestamptz,
  created_at        timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id    uuid not null references public.groups(id) on delete cascade,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  role        text not null default 'member' check (role in ('owner','member')),
  joined_at   timestamptz not null default now(),
  primary key (group_id, profile_id)
);

-- Auto-add the creator as owner.
create or replace function public.add_group_owner()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.group_members (group_id, profile_id, role)
  values (new.id, new.created_by, 'owner')
  on conflict do nothing;
  return new;
end$$;

drop trigger if exists on_group_created on public.groups;
create trigger on_group_created
  after insert on public.groups
  for each row execute function public.add_group_owner();

-------------------------------------------------------------------------------
-- expenses + shares
-------------------------------------------------------------------------------
create table if not exists public.expenses (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups(id) on delete cascade,
  description   text not null,
  amount        numeric(14,2) not null check (amount > 0),
  currency      text not null,
  fx_to_group   numeric(18,8) not null default 1,
  paid_at       date not null default current_date,
  category      text not null default 'general',
  note          text,
  created_by    uuid not null references public.profiles(id),
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create index if not exists expenses_group_idx on public.expenses(group_id, paid_at desc);

create table if not exists public.expense_shares (
  expense_id   uuid not null references public.expenses(id) on delete cascade,
  profile_id   uuid not null references public.profiles(id),
  paid_share   numeric(14,2) not null default 0,
  owed_share   numeric(14,2) not null default 0,
  primary key (expense_id, profile_id)
);

-- Enforce sum(paid) = sum(owed) = amount per expense.
create or replace function public.validate_expense_shares()
returns trigger language plpgsql as $$
declare
  exp_amount numeric(14,2);
  s_paid     numeric(14,2);
  s_owed     numeric(14,2);
begin
  select amount into exp_amount from public.expenses where id = coalesce(new.expense_id, old.expense_id);
  select coalesce(sum(paid_share),0), coalesce(sum(owed_share),0)
    into s_paid, s_owed
    from public.expense_shares
    where expense_id = coalesce(new.expense_id, old.expense_id);
  if s_paid <> exp_amount or s_owed <> exp_amount then
    raise exception 'Share totals (paid=%, owed=%) must match expense amount (%)', s_paid, s_owed, exp_amount;
  end if;
  return null;
end$$;

drop trigger if exists trg_validate_shares on public.expense_shares;
create constraint trigger trg_validate_shares
  after insert or update or delete on public.expense_shares
  deferrable initially deferred
  for each row execute function public.validate_expense_shares();

-------------------------------------------------------------------------------
-- settlements
-------------------------------------------------------------------------------
create table if not exists public.settlements (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups(id) on delete cascade,
  from_profile  uuid not null references public.profiles(id),
  to_profile    uuid not null references public.profiles(id),
  amount        numeric(14,2) not null check (amount > 0),
  currency      text not null,
  note          text,
  created_at    timestamptz not null default now(),
  check (from_profile <> to_profile)
);

-------------------------------------------------------------------------------
-- activity feed
-------------------------------------------------------------------------------
create table if not exists public.activity_events (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid references public.groups(id) on delete cascade,
  actor       uuid not null references public.profiles(id),
  kind        text not null,
  target_id   uuid not null,
  payload     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists activity_group_idx on public.activity_events(group_id, created_at desc);

-------------------------------------------------------------------------------
-- Row-Level Security
-------------------------------------------------------------------------------
alter table public.profiles         enable row level security;
alter table public.groups           enable row level security;
alter table public.group_members    enable row level security;
alter table public.expenses         enable row level security;
alter table public.expense_shares   enable row level security;
alter table public.settlements      enable row level security;
alter table public.activity_events  enable row level security;

-- helper: is the current user a member of this group?
create or replace function public.is_group_member(g uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.group_members
    where group_id = g and profile_id = auth.uid()
  );
$$;

-- profiles
create policy "self can read own profile" on public.profiles
  for select using (id = auth.uid());
create policy "group peers can read profile" on public.profiles
  for select using (
    exists (
      select 1
      from public.group_members me, public.group_members them
      where me.profile_id = auth.uid()
        and them.profile_id = profiles.id
        and me.group_id = them.group_id
    )
  );
create policy "self can update own profile" on public.profiles
  for update using (id = auth.uid());

-- groups
create policy "members can read groups" on public.groups
  for select using (public.is_group_member(id));
create policy "anyone can create a group" on public.groups
  for insert with check (created_by = auth.uid());
create policy "owners can update groups" on public.groups
  for update using (
    exists (select 1 from public.group_members
            where group_id = groups.id and profile_id = auth.uid() and role = 'owner')
  );

-- group_members
create policy "members read membership" on public.group_members
  for select using (public.is_group_member(group_id));
create policy "owners add members" on public.group_members
  for insert with check (
    exists (select 1 from public.group_members
            where group_id = group_members.group_id and profile_id = auth.uid() and role = 'owner')
    or profile_id = auth.uid()
  );

-- expenses
create policy "members read expenses" on public.expenses
  for select using (public.is_group_member(group_id));
create policy "members add expenses" on public.expenses
  for insert with check (public.is_group_member(group_id) and created_by = auth.uid());
create policy "creator edits expense" on public.expenses
  for update using (created_by = auth.uid());

-- expense_shares
create policy "members read shares" on public.expense_shares
  for select using (
    exists (select 1 from public.expenses e
            where e.id = expense_shares.expense_id
              and public.is_group_member(e.group_id))
  );
create policy "members write shares" on public.expense_shares
  for insert with check (
    exists (select 1 from public.expenses e
            where e.id = expense_shares.expense_id
              and e.created_by = auth.uid())
  );

-- settlements
create policy "members read settlements" on public.settlements
  for select using (public.is_group_member(group_id));
create policy "members add settlements" on public.settlements
  for insert with check (public.is_group_member(group_id)
                        and (from_profile = auth.uid() or to_profile = auth.uid()));

-- activity
create policy "members read activity" on public.activity_events
  for select using (group_id is null or public.is_group_member(group_id));
create policy "members write activity" on public.activity_events
  for insert with check (actor = auth.uid());
