# Tabby — Project Status

*Last updated 2026-05-25. Keep this file current: update it in the same commit as the feature it describes.*

> **Session summary (2026-05-25):** shipped multi-currency, receipt photos, splash screen, simplify-debts toggle, archive UX polish, app icon, and full dark-theme support. Multi-currency: FX snapshot at entry, balance math conversion, 14-currency picker defaulting to group currency. Receipts: private Storage bucket + RLS, `ReceiptsRepository`, horizontal thumbnail strip with full-screen viewer on expense detail (run migration 0009). Splash: `flutter_native_splash` generates warm-paper (#FBFAF6) and dark (#11151A) backgrounds for Android + iOS. Simplify-debts: toggle in the group balance strip switches between "Your transfers" (simplified, tappable → SettleSheet) and "Everyone's balance" (raw net positions). Archive polish: archived section in Groups tab is now a collapsible `ExpansionTile` showing the count; New Group currency picker expanded from 5 hardcoded codes to all 14 via `FxRates.supported`.

---

## Shipped

Everything below is committed (or sitting in the working tree as an uncommitted finish-line item — see note at the end of each section).

### v0.1 — scaffold
- **Auth flow** — email magic-link sign-up/sign-in via Supabase Auth; `authStateProvider` drives top-level routing so the app lands on Home or Sign-in deterministically.
- **Groups list + create** — `myGroupsProvider` fetches the user's groups; create-group sheet writes to `groups` + lets the server trigger (`add_group_owner`) seed the owner row in `group_members` (client never writes `group_members` directly — avoids the 42501 UPDATE-policy trap).
- **Equal-split expense (bare minimum)** — add an expense with equal split across all members; `expense_shares` rows written atomically.
- **Balances (per-group, equal only)** — `groupBalanceProvider` computes net position from expenses + settlements.

### v0.2 — split modes, members, expense detail
- **All four split modes** — Equal / Unequal / Percent / Shares in `add_expense_screen.dart`; `SplitEngine` enforces invariants and absorbs rounding onto the last participant.
- **Members sheet** — invite by email via `find_profile_by_email` RPC (SECURITY DEFINER so non-peers can be looked up without exposing the `profiles` table); member list with role badges.
- **Expense detail bottom sheet** — read-only view of amount, payer, shares, note, category, date.
- **Per-group balance strip** — compact "you owe / you're owed" card at the top of Group detail.
- **Global balances tab** — `balancesRollupProvider` rolls up net positions across all groups per peer; tap a peer card to drill into a breakdown sheet.

### v0.3 — activity, settle-up, profile, and hardening

#### Features
- **Activity feed (global)** — `activityFeedProvider` renders `activity_events` rows as a scrollable feed on the Activity tab; `ActivityRow` widget handles all event kinds with avatar, tint, and tap navigation.
- **Per-group activity sheet** — second tab on Group detail; same `ActivityRow` renderer scoped to `groupActivityProvider`.
- **Settle-up** — `SettleSheet` can be triggered from the balance strip ("Settle up" button) and from the peer breakdown card on the Balances tab; writes a `settlements` row and invalidates expenses + balance + rollup + activity.
- **Settlement detail + delete** — tap a settle row in the expense list to see amount, parties, note; owner or either party can hard-delete (RLS in `0005`); AFTER DELETE trigger purges the matching `settle` activity row.
- **Soft-delete expense** — sets `deleted_at`; excluded from balance math; shown as a struck-through tombstone in the expense list with a brief summary for the activity feed.
- **Edit expense** — `update_expense_with_shares` SECURITY DEFINER RPC (migration `0006`) atomically replaces the expense row + all its shares in one call; relies on the `validate_expense_shares` constraint being DEFERRABLE INITIALLY DEFERRED so the delete-then-insert doesn't trip the check mid-transaction.
- **Archive group** — owner-only; sets `archived_at`; archived groups show in a collapsed "Archived" section on the Groups tab and are excluded from balance rollup.
- **Delete group** — owner-only; hard-delete cascades to expenses, shares, settlements, activity (all `ON DELETE CASCADE` from `0001`); RLS policy in `0004`; `.select()` guard catches the RLS-silent-success case.
- **Profile editing** — display name + default currency editable from the Me tab; `myProfileProvider` invalidated on save.
- **Member remove + leave** *(uncommitted — working tree)* — owners can remove non-owner members; any member can self-leave; balance-aware confirm dialog lists open transfers before letting the user go; leaver is navigated home and loses RLS access; activity trigger writes `group.member.remove` with a `self_leave` flag (migration `0007`).

#### Infrastructure fixes
- **Auth-cache fix** — every per-user `FutureProvider` now calls `ref.watch(authStateProvider)` so cached `AsyncValue`s from a prior session are dropped on sign-out / sign-in. Applied to all providers in `groups_repository.dart`, `expenses_repository.dart`, `settlements_repository.dart`, `balance_providers.dart`, `activity_repository.dart`.
- **RLS-silent-success fix** — `deleteGroup`, `softDelete` (expenses), `delete` (settlements), and `removeMember` all chain `.select()` and raise when the returned list is empty, so the UI never shows a misleading success snackbar when RLS filtered the row.
- **Cascade-FK fix** *(migration `0008`)* — the `log_member_remove_activity` trigger now guards with `if not exists (select 1 from groups where id = old.group_id)` so a group delete doesn't 23503 when the cascade tears down `group_members` after the parent `groups` row is already gone.

---

## Deferred — decided against for now, and why

| Item | Why deferred |
|------|-------------|
| **Invite system** (email invite → deep link → join) | Requires app-store-registered Universal Links / App Links, a Supabase Edge Function + Resend for transactional email, and contact-list permission handling. None of that makes sense before the app is on the stores. Revisit post-launch as the highest-value post-ship feature. |
| **Ownership transfer** | Low demand; the owner-delete flow (owner deletes themselves → group goes too) is the correct exit path for v1. No UI affordance added. |
| **Date / category / note editing on expenses** | The edit-expense RPC exists but the edit sheet only exposes amount, split, and payer. Adding date needs a proper date-picker widget; category needs the full slug list. Deferred until those widgets are ready rather than shipping a half-baked form. |
| **Live FX rates** | Multi-currency data entry hasn't shipped yet. Pulling live rates before the input UX exists would be premature. Deferred to post-multi-currency. |

---

## Pre-production roadmap (finish before submitting to stores)

These are the remaining items on the plate before the app is ready for TestFlight / Play Internal Testing.

### ~~Multi-currency~~ ✅ shipped
`lib/core/fx_rates.dart` — 14-currency static rate table. `BalanceCalculator.compute()` multiplies each share by `e.fxToGroup`. Add/Edit expense defaults currency to group default, computes `fxToGroup` via `FxRates.rate()` at save time. Balance strip shows currency code + properly rounded amounts.

### ~~Receipts~~ ✅ shipped (run migration 0009 in Supabase Studio)
Private `receipts` Storage bucket + RLS (migration 0009). `ReceiptsRepository` (upload/list/delete with signed URLs). `_ReceiptStrip` on expense detail: horizontal scrollable thumbnails, full-screen `InteractiveViewer` on tap, delete button for creator, "Add" tile for creator (max 5).

### Production prep chores
| Chore | Detail |
|-------|--------|
| **Disable email confirmation** | In Supabase Auth settings → disable "Confirm email" for magic-link flow, or users get stuck after sign-up. |
| ~~**`.gitattributes` for CRLF**~~ ✅ | `* text=auto` + `*.dart/sql/yaml/json/md text eol=lf`; platform dirs marked binary. |
| ~~**App icon**~~ ✅ | Geometric cat face (white head + ears, three amber tabby/ledger stripes, teal bg). Generated via `test/gen_icon_test.dart` → `assets/icon/icon.png`; `flutter_launcher_icons` emits all Android mipmap densities + adaptive icon + iOS `AppIcon.appiconset`. |
| ~~**Launch / splash screen**~~ ✅ | `flutter_native_splash` generates warm-paper (#FBFAF6) / dark (#11151A) backgrounds for Android + iOS. |
| **Bundle IDs** | Set `com.tabby.app` (or chosen ID) in `android/app/build.gradle` and Xcode; must match what's registered in App Store Connect / Play Console. |

---

## Post-production roadmap (after stores ship the app)

These only pay off once there's an install base.

| Item | Notes |
|------|-------|
| **Invite system** | Email invite via Edge Function + Resend; deep link lands new user in the group after sign-up; optional contact-list scan to surface friends already on Tabby. Needs Universal Links (iOS) + App Links (Android) registered against the production domain. |
| **Live FX rates** | Scheduled Edge Function fetches ECB / Open Exchange Rates daily, writes to a `fx_rates` table; `add_expense_screen` reads the latest rate at entry time instead of a static table. |
| **OCR for receipts** | On photo attach, call a Vision API (Google ML Kit on device, or a Cloud Vision Edge Function) to pre-fill amount + description. Pure UX sugar — skip if the static receipt attach ships and users are happy. |
| **Push notifications** | Supabase Database Webhooks → Edge Function → APNs / FCM when a new expense or settlement is added to a group you're in. Requires APNs key in App Store Connect + FCM key in Play Console. |
| **Offline-first reads via Drift** | Mirror `expenses`, `expense_shares`, `groups`, `group_members`, `settlements` into local SQLite via Drift; load from cache on cold start, reconcile in background. High effort; only worth it once users complain about loading states on slow connections. |
| **Friend list (1:1 groups)** | Treat a 2-person group as a "friendship"; surface these differently on the Balances tab. Likely a v1.1 UI reskin rather than a schema change. |
| **CSV export** | Dump a group's expenses as CSV for the "I want a spreadsheet" power user. Single endpoint, low effort, high goodwill. |
| **Recurring expenses** | Scheduled entries (monthly rent, subscriptions). Needs a `recurrence_rule` column + a cron-like Edge Function or client-side scheduler. |
| **Search** | Full-text search over expense descriptions. Postgres `tsvector` + GIN index on `expenses.description`; expose via RPC. |
| ~~**Dark theme polish**~~ ✅ | `TabbyTheme.dark()` completed (`inputDecorationTheme`, `scrolledUnderElevation`); three semantic helpers (`dimOf`, `cardFillOf`, `borderOf`) replace hardcoded `dim`/`Colors.white`/`mist` references across 12 UI files so all colours adapt to light/dark automatically. |
