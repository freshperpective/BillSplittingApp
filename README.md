# Sorted

A clean, original bill-splitting app for Android and iOS. Built with **Flutter + Supabase**.

> **Bundle ID:** `com.sorted.app`  
> **Status:** Pre-production — all core features shipped, pending store submission.

---

## What it does

Sorted lets a group of people track shared expenses and settle up cleanly.

| Feature | Detail |
|---------|--------|
| **Groups** | Create named groups with an emoji + currency; invite members by email |
| **Expenses** | Equal / Unequal / Percent / Shares / Adjust split modes; any member can pay |
| **Multi-currency** | Per-expense currency with FX snapshot at entry time; balances converted to group currency |
| **Receipts** | Attach up to 5 photos per expense; stored in a private Supabase Storage bucket |
| **Settle up** | Record a payment between two members; balance updates immediately |
| **Simplify debts** | Toggle between "your transfers" (minimum-transfer graph) and everyone's raw net position |
| **Activity feed** | Global + per-group timeline of all expense, settlement, and membership events |
| **Archive** | Archive old groups; collapsible section keeps the list clean |
| **Dark theme** | Full dark/light support; all colours adapt via semantic theme helpers |
| **Profile** | Edit display name and default currency |

## Originality

No code, asset, copy, or visual element is taken from Splitwise or any other app. The "warm ledger" theme — teal `#0E7C66`, amber `#F4A259`, paper `#FBFAF6`, Inter + Fraunces — was designed to be visually distinct. The split math (zero-sum balance reconciliation) is public-domain arithmetic.

---

## Tech stack

| Layer | Choice |
|-------|--------|
| UI | Flutter 3.22+ / Dart 3.4 |
| State | Riverpod 2.5 |
| Routing | go_router 14 |
| Backend | Supabase (Postgres + Auth + Storage) |
| Money | `decimal` package — never `double` |

---

## Project structure

```
lib/
├── main.dart                  — entrypoint, Supabase init
├── app.dart                   — MaterialApp, theme, router
├── core/                      — pure Dart (no Flutter/Supabase imports)
│   ├── models.dart            — Group, Expense, ExpenseShare, Settlement, Profile, Receipt
│   ├── money.dart             — currency formatting helpers
│   ├── fx_rates.dart          — static FX rate table (14 currencies)
│   ├── split_engine.dart      — equal/unequal/percent/shares/adjust + BalanceCalculator
│   └── env.dart               — dart-define accessors
├── data/                      — Supabase repositories + Riverpod providers
│   ├── supabase_client.dart
│   ├── groups_repository.dart
│   ├── expenses_repository.dart
│   ├── settlements_repository.dart
│   ├── receipts_repository.dart
│   ├── activity_repository.dart
│   ├── profiles_repository.dart
│   └── balance_providers.dart
└── ui/
    ├── theme/sorted_theme.dart — light / grey / dark themes, semantic colour helpers
    ├── screens/
    │   ├── auth_screen.dart
    │   ├── add_expense_screen.dart
    │   ├── expense_detail_screen.dart
    │   ├── group_detail_screen.dart
    │   ├── settlement_detail_screen.dart
    │   └── tabs/              — balances, groups, activity, profile
    └── widgets/               — ActivityRow, SettleSheet, reusable components

supabase/migrations/           — SQL applied via Supabase Studio (run in order)
test/
├── split_engine_test.dart     — unit tests (no network/Flutter harness needed)
└── gen_icon_test.dart         — generates assets/icon/icon.png
```

---

## Getting started

### Prerequisites

- Flutter 3.22+ (`flutter doctor` should be green for Android + iOS)
- A [Supabase](https://supabase.com) project (free tier is fine)

### 1. Apply migrations

In **Supabase Studio → SQL editor**, run each file in `supabase/migrations/` in order:

| File | What it does |
|------|-------------|
| `0001_init.sql` | Tables, RLS, validate-shares trigger, `is_group_member` helper |
| `0002_find_profile_by_email.sql` | `find_profile_by_email` SECURITY DEFINER RPC |
| `0003_activity_triggers.sql` | Activity event triggers + idempotent backfill |
| `0004_group_delete_policy.sql` | Owner-only DELETE on `groups` |
| `0005_settlement_delete.sql` | DELETE on `settlements` + purge-activity trigger |
| `0006_update_expense_rpc.sql` | `update_expense_with_shares` SECURITY DEFINER RPC |
| `0007_member_remove.sql` | DELETE on `group_members` + `group.member.remove` trigger |
| `0008_cascade_guard.sql` | Guards the member-remove trigger against cascade FK violation |
| `0009_receipts.sql` | `receipts` Storage bucket + `expense_receipts` table + RLS |

> **Never edit a migration that's already been applied.** Add a new numbered file instead.

### 2. Configure Supabase Auth

In **Authentication → Providers → Email**: disable **"Confirm email"**. Magic-link auth proves ownership in one click — the confirmation step is redundant and breaks the sign-up flow.

### 3. Run

```bash
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

### 4. Test

```bash
flutter test                                        # all tests
flutter test test/split_engine_test.dart            # split engine only
flutter test --plain-name 'equal split rounding'    # single test
flutter analyze                                     # must be clean
```

---

## Release builds

```bash
# Android App Bundle (Play Store)
flutter build appbundle \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...

# iOS IPA (App Store / TestFlight)
flutter build ipa \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

Store the dart-define values as CI secrets — never commit them to the repo.

---

## Architecture notes

**Layer rule:** UI consumes providers only → providers wrap repositories → repositories call Supabase → repositories depend on core models. Never reach upward.

**Riverpod providers live in `lib/data/`**, not in screen files. Providers declared in UI files caused import cycles with the cross-group balance rollup during v0.3 refactor.

**Money is always `Decimal`** from the `decimal` package. Database columns are `numeric(14,2)`. Never use `double` for currency arithmetic.

**RLS silent-success on UPDATE/DELETE:** PostgREST returns success even when RLS filters out every row. Every destructive repository call chains `.select()` and raises if the result is empty:

```dart
final res = await _client.from('groups').delete().eq('id', id).select();
if (res.isEmpty) throw Exception('Delete failed or not permitted.');
```

**Auth cache invalidation:** Every per-user `FutureProvider` calls `ref.watch(authStateProvider)` at the top so cached values are dropped on sign-out/sign-in.

See `DESIGN.md` for the full architectural blueprint.

---

## License

This codebase is yours. Add a `LICENSE` file when publishing — MIT or Apache-2.0 are standard.
