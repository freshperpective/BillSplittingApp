# Contributing to Tabby

## Dev environment

| Tool | Version |
|------|---------|
| Flutter | 3.22+ |
| Dart | 3.4+ |
| Android Studio / Xcode | latest stable |

```bash
# Verify your setup
flutter doctor

# Install dependencies
flutter pub get
```

## Running the app

Supabase credentials are passed at run time — never committed. Get them from **Supabase → Project Settings → API**.

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

For VS Code, add a `.vscode/launch.json`:

```json
{
  "configurations": [
    {
      "name": "Tabby (debug)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co",
        "--dart-define=SUPABASE_ANON_KEY=eyJ..."
      ]
    }
  ]
}
```

## Before every commit

```bash
flutter analyze   # must be clean — zero issues
flutter test      # must pass
```

The analyzer enforces `prefer_single_quotes`, `require_trailing_commas`, `avoid_print`, strict casts, and strict raw types. Run `dart fix --apply` to auto-correct most style issues.

## Layer rules

```
ui/         ← consumes Riverpod providers only
data/       ← repositories + providers (never declare providers in UI files)
core/       ← pure Dart, zero Flutter or Supabase imports
```

Never reach upward between layers.

## Adding a migration

1. Create `supabase/migrations/NNNN_description.sql` (next number in sequence).
2. Add a header comment block explaining the motivation.
3. Apply it manually via **Supabase Studio → SQL editor**.
4. **Never edit a migration that's already been applied** — add a new file instead.

## Money arithmetic

Always use `Decimal` from the `decimal` package. Never `double`. Database columns are `numeric(14,2)`.

```dart
// correct
final total = Decimal.parse('19.99') + Decimal.parse('5.01');

// wrong — floating-point drift
final total = 19.99 + 5.01;
```

## Riverpod conventions

- Providers live in `lib/data/`, not in screen files.
- Every per-user `FutureProvider` must call `ref.watch(authStateProvider)` at the top to bust the cache on auth change.
- After any mutation that touches money or membership, invalidate: per-group expenses, per-group balance, cross-group rollup, global activity, and per-group activity. See `add_expense_screen.dart` save handler for the canonical example.

## RLS silent-success guard

PostgREST returns success even when zero rows are affected by an UPDATE or DELETE (RLS filtered them out). Every destructive call must chain `.select()` and raise when the result is empty:

```dart
final res = await _client.from('table').delete().eq('id', id).select();
if (res.isEmpty) throw Exception('Operation failed or not permitted.');
```

## Async + BuildContext

Always add an `if (!context.mounted) return;` (or `if (!mounted) return;` inside a `State` method) before using `context` after any `await`.

## Windows development note

Kotlin incremental compilation is disabled in `android/gradle.properties` due to a cross-drive caching bug. Don't re-enable it.

When staging files, only stage `lib/`, `test/`, `supabase/`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `README.md`, `DESIGN.md`, `CLAUDE.md`, and `CONTRIBUTING.md`. Platform directories (`android/`, `ios/`, `macos/`, etc.) show spurious CRLF-related diffs on Windows — only stage intentional changes in those dirs by file path.
