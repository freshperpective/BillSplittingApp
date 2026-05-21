# Tabby

A cross-platform bill-splitting app for Android and iOS. Built with **Flutter** (one codebase, native rendering on both platforms) and **Supabase** (Postgres + auth + storage + realtime).

This repo is an original implementation: no Splitwise code, assets, copy, or visual styling was used. The data model and split math come from first principles. See `DESIGN.md` for the full architectural blueprint.

## What's here

```
.
├── DESIGN.md                  ← read this first
├── pubspec.yaml               ← Flutter dependencies
├── lib/
│   ├── main.dart              ← entrypoint, Supabase init
│   ├── app.dart               ← MaterialApp + theme + router
│   ├── core/                  ← pure Dart: models, money, split engine
│   │   ├── env.dart
│   │   ├── models.dart
│   │   ├── money.dart
│   │   └── split_engine.dart  ← equal/unequal/%/shares + balance + simplify
│   ├── data/                  ← Supabase repositories
│   │   ├── supabase_client.dart
│   │   ├── groups_repository.dart
│   │   └── expenses_repository.dart
│   └── ui/
│       ├── router.dart
│       ├── theme/tabby_theme.dart
│       └── screens/           ← auth, home shell, group detail, add expense
├── test/
│   └── split_engine_test.dart
└── supabase/
    └── migrations/0001_init.sql
```

## Stack at a glance

| Layer        | Choice                              |
|--------------|-------------------------------------|
| UI           | Flutter 3.22+ (Dart 3.4)            |
| State        | Riverpod 2.5                        |
| Routing      | go_router 14                        |
| Backend      | Supabase (Postgres, Auth, Storage)  |
| Money        | `decimal` (never `double`)          |
| Local cache  | Drift (SQLite) — wired in v0.2      |

## Getting started

### 1. Install Flutter

Install Flutter 3.22 or newer per the [official guide](https://docs.flutter.dev/get-started/install), then:

```bash
flutter doctor
```

Make sure the Android toolchain + Xcode (on macOS) come up green.

### 2. Create a Supabase project

1. Sign up at [supabase.com](https://supabase.com) and create a new project (free tier is fine).
2. In the project's SQL editor, paste the contents of `supabase/migrations/0001_init.sql` and run it. This creates all tables, triggers, and RLS policies.
3. Under **Authentication → Providers**, enable **Email**. Optionally enable **Apple** and **Google** later for production.
4. Copy your project URL and `anon` public key from **Project Settings → API**.

### 3. Run the app

```bash
flutter pub get

# Android emulator or iOS simulator must be running.
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIs...
```

For iOS-specific setup: open `ios/Runner.xcworkspace` once, set the bundle ID and signing team. For Android: the default `applicationId` lives in `android/app/build.gradle`.

### 4. Run the tests

```bash
flutter test
```

The split engine has unit tests; running these does not need Supabase.

## Building releases

```bash
# Android (App Bundle for Play Store)
flutter build appbundle \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...

# iOS (archive for App Store / TestFlight)
flutter build ipa \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

For CI, store the dart-define values as secrets — never commit them.

## Originality notes

- **Color palette, typography, iconography, copy:** all chosen independently. The "warm ledger" theme (deep teal `#0E7C66` + warm amber `#F4A259` on warm paper `#FBFAF6`, with Inter + Fraunces) is distinct from Splitwise's brand.
- **Data model:** derived from the public math of balance reconciliation. Schema, table names, and constraints are original.
- **Split-engine math:** equal/unequal/percent/shares splits are standard arithmetic; the implementation in `lib/core/split_engine.dart` is original Dart.
- **What is *not* original (and doesn't need to be):** the *idea* of bill splitting and the public-domain math of zero-sum balance reconciliation. Trademarks and product names belong to their owners.

## Roadmap

See `DESIGN.md §11`. Short version: v0.1 is this scaffold (auth, groups, equal-split expenses); v0.2 adds all split modes + settle-up + activity feed; v0.3 adds multi-currency + receipts; v1.0 ships to TestFlight/Play Internal Testing.

## License

You own this codebase. Add a `LICENSE` file when you publish — MIT or Apache-2.0 are common defaults.
