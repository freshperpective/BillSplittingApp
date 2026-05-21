# Tabby — Bill Splitting App

A clean, original group-expense tracker for Android and iOS. Built with Flutter + Supabase. This document is the architectural blueprint; the source code that follows implements it.

## 1. Why this exists

Splitwise solved the "who paid for what on the trip" problem a decade ago, but its mobile UX has aged: dense list rows, an aggressive paywall around basic features, and ad placements that interrupt the core flow. Tabby keeps the math and rebuilds the experience around three opinions:

1. **Adding an expense should feel like sending a message** — three taps, not a form.
2. **Balances are the headline**, not a sub-screen. The home tab should immediately answer "who do I owe and who owes me?"
3. **Receipts and notes belong to the expense**, not a separate scanner upsell.

No code, asset, copy, or visual element is taken from Splitwise. The data model is derived from first principles (the math of split-balance reconciliation is public-domain).

## 2. Product scope (MVP)

| Area | In scope | Out of scope (v1) |
|------|----------|-------------------|
| Auth | Email + magic link, Apple sign-in, Google sign-in | Phone OTP, SSO |
| Groups | Create, rename, add/remove members, archive | Sub-groups, group templates |
| Friends | Friend list, 1:1 expenses (treated as a 2-person group internally) | Friend requests/handshake |
| Expenses | Equal / unequal / percent / shares split; multi-payer | Recurring expenses |
| Currency | Multi-currency per expense + fx snapshot at entry time | Live conversion in summaries (uses snapshot) |
| Receipts | Photo attach (≤5 per expense, 5 MB each) | OCR auto-fill |
| Settlements | Manual "mark as settled", simplify-debts toggle | In-app payments / UPI |
| Activity | Per-group and global feed with edit/delete history | Push notifications (v1.1) |
| Offline | Read recent groups + draft expenses offline, sync on resume | Full offline-first CRDT |

## 3. Tech stack

| Layer | Choice | Reason |
|-------|--------|--------|
| UI | Flutter 3.22+ (Dart 3.4) | One codebase, true-native rendering on iOS/Android |
| State | Riverpod 2.5 (code-gen) | Compile-time safety, no `BuildContext` coupling in business logic |
| Routing | go_router 14 | Declarative, deep-link friendly |
| Backend | Supabase (Postgres + Auth + Storage + Realtime) | SQL gives us correct money math; RLS gives us per-row security without a custom server |
| Local cache | Drift (SQLite) | Offline reads, query parity with server schema |
| HTTP | supabase_flutter SDK (wraps Dio) | Streamed realtime + REST + storage in one |
| Money | `decimal` package | Never use `double` for currency |
| Testing | flutter_test, mocktail, integration_test | Standard set |

## 4. Architecture

A standard layered Flutter app with strict downward dependencies:

```
  ┌────────────────────────────────────────────────────────────┐
  │  ui/                  Widgets, screens, theme              │
  │     ↓ consumes Riverpod providers only                     │
  ├────────────────────────────────────────────────────────────┤
  │  features/<name>/     Per-feature controllers + view-state │
  │     ↓ depends on repositories                              │
  ├────────────────────────────────────────────────────────────┤
  │  data/                Repositories, DTOs, Supabase client  │
  │     ↓ depends on core/                                     │
  ├────────────────────────────────────────────────────────────┤
  │  core/                Models, split engine, money, errors  │
  │     (pure Dart, no Flutter or Supabase imports)            │
  └────────────────────────────────────────────────────────────┘
```

Pure-Dart `core/` is the load-bearing piece: the split engine and balance reconciliation are unit-tested without a Flutter or network harness.

## 5. Data model

Six tables. All amounts stored as `numeric(14,2)`; all timestamps `timestamptz`. UUIDs everywhere.

### `profiles`
Mirrors `auth.users` with display info.
- `id uuid PK` (= auth.uid)
- `display_name text`
- `avatar_url text`
- `default_currency text` (ISO-4217)
- `created_at timestamptz`

### `groups`
- `id uuid PK`
- `name text`
- `emoji text` — group avatar (single grapheme, e.g. 🏖️)
- `default_currency text`
- `created_by uuid → profiles.id`
- `archived_at timestamptz null`
- `created_at timestamptz`

### `group_members`
Many-to-many between profiles and groups.
- `group_id uuid → groups.id`
- `profile_id uuid → profiles.id`
- `role text check (role in ('owner','member'))`
- `joined_at timestamptz`
- PK `(group_id, profile_id)`

### `expenses`
- `id uuid PK`
- `group_id uuid → groups.id`
- `description text`
- `amount numeric(14,2)` — total, always positive
- `currency text` — ISO-4217, may differ from group default
- `fx_to_group numeric(18,8)` — snapshot rate at entry (1.0 if same currency)
- `paid_at date`
- `category text` — short slug ("food","travel",…)
- `note text null`
- `created_by uuid → profiles.id`
- `created_at timestamptz`
- `deleted_at timestamptz null` — soft delete for activity feed

### `expense_shares`
One row per participant per expense. Captures both who paid and who owes.
- `expense_id uuid → expenses.id`
- `profile_id uuid → profiles.id`
- `paid_share numeric(14,2)` — amount this person paid toward the expense
- `owed_share numeric(14,2)` — amount this person ultimately owes
- PK `(expense_id, profile_id)`

Invariant per expense: `sum(paid_share) = sum(owed_share) = amount`. The split engine enforces this; a CHECK constraint via a trigger backs it up server-side.

### `settlements`
A "Person A paid Person B X" record. Treated as a 1-payer/1-payee virtual expense for balance math.
- `id uuid PK`
- `group_id uuid → groups.id`
- `from_profile uuid → profiles.id`
- `to_profile uuid → profiles.id`
- `amount numeric(14,2)`
- `currency text`
- `note text null`
- `created_at timestamptz`

### `activity_events`
Append-only audit log powering the activity feed.
- `id uuid PK`
- `group_id uuid null`
- `actor uuid → profiles.id`
- `kind text` — `expense.add | expense.edit | expense.delete | settle | group.create | group.member.add`
- `target_id uuid` — points at the expense/settlement/group
- `payload jsonb` — denormalized snapshot for fast feed rendering
- `created_at timestamptz`

### Row-Level Security (sketch)

Every table has RLS on. A user can see a row only if they are a member of the row's group:

```sql
create policy "members read expenses"
  on expenses for select
  using (exists (
    select 1 from group_members gm
    where gm.group_id = expenses.group_id
      and gm.profile_id = auth.uid()
  ));
```

Insert/update/delete policies follow the same membership check, with additional `created_by = auth.uid()` on edits.

## 6. Balance math (the only "secret sauce")

For any group, each member's net balance is:

```
balance(p) = Σ paid_share(p, e)  -  Σ owed_share(p, e)
           + Σ amount(s where to_profile=p)
           - Σ amount(s where from_profile=p)
```

`Σ balance(p) = 0` for the whole group by construction.

**Simplify debts** is an optional view: given the net balances, build the minimum-transfer graph by repeatedly settling the largest creditor with the largest debtor. This is O(n log n) and stable. It runs client-side from cached balances; no server roundtrip.

## 7. Split modes (input → output)

The split engine takes a total `T` and `n` participants and produces `owed_share` per participant:

| Mode | Input | Algorithm |
|------|-------|-----------|
| Equal | participants list | `T / n`, last person absorbs rounding cent |
| Unequal | per-person amount | sum must equal `T` (validated) |
| Percent | per-person % | sum must equal 100%; `owed = T * pct / 100`, last absorbs rounding |
| Shares | per-person share count | `owed = T * share / Σshares`, last absorbs rounding |

All arithmetic uses `Decimal` and rounds to currency-aware decimal places (2 for INR/USD/EUR, 0 for JPY, etc.).

Paid amounts are independent: any subset of participants may have paid any portion, as long as `Σ paid_share = T`. This natively supports "Alice and Bob each paid half the bill" without a separate UX.

## 8. Screen map

```
┌─ Auth ───────────────────────┐
│  Sign in (email + Apple/G)   │
└──────────────────────────────┘
           │ on success
           ▼
┌─ Home (bottom-tab) ──────────────────────┐
│  [Balances] [Groups] [Activity] [Me]     │
└──────────────────────────────────────────┘
   │            │             │         │
   │            │             │         └─► Profile / settings / sign out
   │            │             │
   │            │             └─► Activity feed (all groups, filterable)
   │            │
   │            └─► Group list  ─► Group detail
   │                                 │
   │                                 ├─► Add expense  (FAB)
   │                                 ├─► Settle up
   │                                 ├─► Members
   │                                 └─► Group settings
   │
   └─► Global balances (per-person rollup across groups)
```

### Key screens

- **Balances tab (home).** Single scrollable list: "You owe Asha ₹450", "Riya owes you ₹1,200". Tap a row → drill-down expense list with that person. This is the screen users open most; it loads from local cache instantly and reconciles in the background.
- **Add expense.** A full-screen sheet, not a stacked form. Three rows: amount, "paid by", "split". Each row opens an inline picker. Default split = equal among all group members. Submit is a single FAB, not a menu item.
- **Group detail.** Expense list reverse-chronological, grouped by month. Pull-to-refresh hits realtime channel for delta. Top card shows your balance in this group.
- **Activity feed.** Mix of expense/settle events with avatars and inline diffs ("Asha changed amount from ₹600 to ₹650").

## 9. Visual language (distinct from Splitwise)

| Token | Tabby | (Splitwise reference — explicitly avoided) |
|-------|-------|---------------------------------------------|
| Primary | `#0E7C66` (deep teal) | Splitwise green |
| Accent | `#F4A259` (warm amber) | — |
| Surface | `#FBFAF6` (warm paper) on light; `#11151A` on dark | white / dark gray |
| Type | Inter (UI) + Fraunces (display/numerics) | Open Sans / system |
| Radius | 14px on cards, 22px on FAB | smaller, more rectangular |
| Iconography | Phosphor (duotone variant) | custom flat |
| Motion | 220 ms cubic-out for sheets; spring on FAB | linear, snappier |

The brand is "warm ledger" — paper-like surfaces, teal/amber palette, mixed sans + serif. None of these choices overlap with Splitwise's brand. The amount typography uses tabular-figure Fraunces so numbers align in lists.

## 10. Offline & sync strategy (v1, simple)

- Drift mirrors `expenses`, `expense_shares`, `groups`, `group_members`, `settlements` locally.
- On app open: load from Drift first (instant), then trigger Supabase fetch in the background and reconcile by `updated_at`.
- Writes go through a queue: optimistic insert into Drift → POST to Supabase → on failure, mark row `pending`, retry on next foreground.
- Conflicts: last-write-wins on edits (acceptable for v1; revisited in v1.2 if users hit it).

## 11. Roadmap

- **v0.1 (this scaffold)** — Auth, groups, equal-split expenses, balances. Single currency.
- **v0.2** — All four split modes, settle-up, activity feed.
- **v0.3** — Multi-currency with fx snapshot, receipt uploads via Supabase Storage.
- **v0.4** — Simplify-debts view, group archive, dark theme polish.
- **v1.0** — Push notifications, deep links from notifications, onboarding flow, beta on TestFlight + Play Internal Testing.
- **v1.1** — Friend list (without groups), CSV export.
- **v1.2** — Recurring expenses, search.

## 12. What's not in this repo

- No payment processing. We track debts; we don't move money. Adding UPI/Stripe is an explicit v2 decision with regulatory scope.
- No analytics SDK by default. If added later, document it in `PRIVACY.md` and respect DPDP consent.
- No Splitwise import path in v1. (Possible later via CSV; not from their API.)

---

*Last updated 2026-05-19. This document leads the code: if you change a screen flow or schema, update this file in the same commit.*
