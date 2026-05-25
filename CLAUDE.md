# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Tabby — a cross-platform bill-splitter for Android and iOS (Flutter + Supabase). README.md has the user-facing tour; `DESIGN.md` is the canonical architectural blueprint and is more current than the README for v0.2+ work. Read DESIGN.md before making non-trivial structural changes.

**Originality is a hard constraint.** No code, copy, asset, theme, or visual element from Splitwise. The "warm ledger" theme (teal `#0E7C66`, amber `#F4A259`, paper `#FBFAF6`, Inter + Fraunces typography) was chosen specifically to be visually distinct. The math (zero-sum balance reconciliation) is public-domain and freely used.

## Commands

```bash
# Setup
flutter pub get

# Run (Supabase URL/key come from --dart-define; no .env file used)
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...

# Tests — split engine has unit tests, no Supabase needed
flutter test
flutter test test/split_engine_test.dart            # single file
flutter test --plain-name 'equal split rounding'    # single named test

# Static analysis (config in analysis_options.yaml)
flutter analyze

# Codegen (Riverpod/Freezed/Drift annotations — most current code is hand-written without codegen,
# but the dev_deps are wired in for when it's needed)
dart run build_runner build --delete-conflicting-outputs

# Release builds (still need the dart-define values)
flutter build appbundle --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
flutter build ipa --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## Architecture

Strict downward dependency layers — never reach upward:

```
ui/         widgets, screens, theme, widgets/ (reusable like SettleSheet, ActivityRow)
  ↓ consumes Riverpod providers only
data/       repositories + Riverpod providers that wrap them
  ↓ depends on core/
core/       pure Dart: models, split engine, money, env
            no Flutter or Supabase imports
```

**Riverpod providers live in `lib/data/*.dart`, not in UI files.** This was refactored mid-v0.3 because UI-layer providers caused import cycles with the cross-group balance rollup. If you find yourself wanting to declare a provider in a screen file, it belongs in `data/`.

`lib/core/split_engine.dart` is load-bearing and pure Dart — equal/unequal/percent/shares/adjust split modes plus `BalanceCalculator.compute()` + `.simplify()` for greedy minimum-transfer reconciliation. Unit-tested without any Flutter or network harness (`test/split_engine_test.dart`). Touch it carefully.

Money: always `Decimal` from package `decimal`. Never `double`. Database columns are `numeric(14,2)`.

## Supabase migrations

SQL files in `supabase/migrations/` numbered `0001_*.sql` upward. They are **run by hand** through the Supabase Studio SQL editor — there is no migration runner in this repo. The numbered ordering matters because later migrations assume earlier ones ran.

**Never edit a migration that's been applied.** Add a new numbered migration that supersedes or amends. The user runs them in production on a single Supabase instance, so editing in place desyncs the schema from the file history.

Current sequence (as of latest work):
- `0001` — initial schema, RLS, validate-shares deferred constraint trigger, helper `is_group_member`.
- `0002` — `find_profile_by_email` SECURITY DEFINER RPC (so non-peers can be looked up by email without exposing `profiles`).
- `0003` — activity event triggers + idempotent backfill keyed by `(kind, target_id)`.
- `0004` — owner-only DELETE policy on `groups`.
- `0005` — DELETE policy on `settlements` + AFTER DELETE trigger that purges the matching `settle` activity row.
- `0006` — `update_expense_with_shares` SECURITY DEFINER RPC (atomic expense+shares edit; relies on `validate_expense_shares` being DEFERRABLE INITIALLY DEFERRED).
- `0007` — DELETE policy on `group_members` (owner-removes or self-leave) + trigger writing `group.member.remove` activity.
- `0008` — patches the 0007 trigger to skip the activity insert when the parent group is gone (otherwise cascade-from-group-delete hits a 23503 FK violation).

## PostgREST gotchas — load-bearing

These have bitten this codebase. Future-Claude should treat them as defaults:

**RLS silent-success on UPDATE/DELETE.** When RLS filters out every matching row, PostgREST returns success affecting zero rows — no exception is raised on the client. The UI then lies about success. Every destructive call in `data/` chains `.select()` and raises if the returned list is empty:

```dart
final res = await _client.from('groups').delete().eq('id', id).select();
if (res is! List || res.isEmpty) throw Exception('...');
```

Applied in `deleteGroup`, `removeMember`, `SettlementsRepository.delete`, `ExpensesRepository.softDelete`. New destructive operations should follow the same pattern.

**Trigger-mirroring + client upserts collide.** If a server-side trigger seeds a row (e.g., the `add_group_owner` trigger inserts into `group_members` after group creation), do *not* also write the same row from the client. A PostgREST upsert with `Prefer: resolution=merge-duplicates` becomes an UPDATE on the existing trigger-inserted row, and `group_members` has no UPDATE policy — surfaces as 42501. The client-side seeding was removed for this reason; don't reintroduce it.

**User-scoped Riverpod providers must invalidate on auth change.** Every per-user `FutureProvider` (`myGroupsProvider`, `groupMembersProvider`, `groupExpensesProvider`, `groupSettlementsProvider`, `groupBalanceProvider`, `balancesRollupProvider`, `activityFeedProvider`, `groupActivityProvider`, `myRoleInGroupProvider`, `groupByIdProvider`, `peerSettleOptionsProvider`, `myProfileProvider`) calls `ref.watch(authStateProvider)` at the top. Without that, signing in as a different user leaks the previous session's cached AsyncValue (which once caused a non-owner to see the owner-only kebab menu).

**Triggers that INSERT into cascade-targeted tables need a guard.** If a trigger fires on AFTER DELETE of a row whose parent might also be cascade-deleting, and the trigger inserts into a table with a FK to the same parent, the insert can hit 23503. See `0008` for the fix pattern: `if not exists (select 1 from public.groups where id = old.group_id) then return old; end if;`.

## Conventions

`analysis_options.yaml` enforces: `prefer_single_quotes`, `require_trailing_commas`, `avoid_print`, `sort_constructors_first`, plus strict casts and strict raw types. Run `flutter analyze` before committing.

Comments in this codebase consistently explain *why* (the constraint, the past bug, the gotcha being defended against), not *what*. Match that style — drive-by formatting changes that strip these comments are a regression.

Migration SQL files have a header comment block explaining the motivation for the change. Maintain that.

When invalidating Riverpod providers after a mutation, cover every read surface — current convention is to bump expenses + balance (per-group) + balances rollup (cross-group) + activity (global) + group activity (per-group) after anything that touches money or membership. See `add_expense_screen.dart`'s save handler as the canonical example.

## Windows-specific quirks

The author develops on Windows with the Flutter pub cache and the project on different drive letters. Kotlin incremental compilation is disabled in `android/gradle.properties` because of a cross-drive caching bug — don't re-enable it.

CRLF noise on platform files (everything under `android/`, `ios/`, `macos/`, etc.) frequently shows up as modified in `git status`. Ignore those when staging — only stage files under `lib/`, `test/`, `supabase/`, plus `pubspec.yaml` / `pubspec.lock` / `analysis_options.yaml` / `README.md` / `DESIGN.md` / `CLAUDE.md`.
