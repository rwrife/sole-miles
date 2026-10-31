# Sole Miles — plan

## Scope and architecture

**Product:** offline gear mileage and rotation ledger for runners/walkers and other recreational athletes. One Flutter codebase runs on Windows, Android, and iOS; phone, tablet, and resizable Windows windows are first-class. Android and iPad tablet support is enabled. Identifier: `com.infinityball.solemiles` for Android applicationId and iOS bundle ID; Windows identity uses `cominfinityball.solemiles` if MSIX packaging is chosen. App Store Connect registration remains blocked by `FORBIDDEN_ERROR.PLA_NOT_ACCEPTED` (see README Manual setup required).

- **Domain:** pure Dart types and reducers for items, activities, distance units, wear states, per-item odometers, and rotation windows; no widget dependency.
- **Persistence:** SQLite under app-private data directory. Records have stable UUIDs, schema version, timestamps, and explicit `null` for unknown distances. Database migrations are additive, tested against old fixtures.
- **User flows:** add/edit/archive item, log/edit/delete activity with undo, wear dashboard, rotation view, CSV export, JSON backup/restore. No background daemon or hosted service.
- **Portability:** JSON backup includes schema version, items, activities, optional encoded photos and timestamps; validate on import and never silently overwrite existing data. Export via platform save dialogs; import in preview mode with an explicit replace/merge choice and a safety backup first.
- **Unit handling:** store canonical meters as integers; display units are prefs, not conversion state. Every activity assigned to at most one gear item in a category. A deleted activity reverses its contribution exactly. Time-based items are deferred rather than pretending km and hours mix.

## Technology and UX

- Flutter stable (exact pin in `toolchain.json`), Dart, SQLite (via an established Flutter plugin), standard platform file picker/share plugins only when needed. Stable channel avoids pre-release churn.
- **UX strategy A — platform-native adaptive:** small adaptive-widget seam (`AdaptiveScaffold`, `AdaptiveButton`, `AdaptiveDialog`), using Cupertino on iOS/iPadOS, Material 3 on Android, and Fluent (`fluent_ui`) on Windows. Screens share domain and view models, not platform chrome. No Material look on iOS, no Cupertino look on Android, no phone-style UI on Windows. This is more useful than a custom brand for a ledger/productivity utility.
- At narrow widths: bottom nav; tablet: navigation rail and two-column details; desktop: Fluent NavigationView, command bar, context menu, hover states and keyboard shortcuts. Native date/file pickers and permission prompts per OS. Back gesture/button and safe areas honored.
- Type scaling, screen-reader names for mileage and wear states, high contrast, 44/48px touch targets and full Windows keyboard navigation are release gates. Distinct colors plus text labels indicate wear state (never color alone).
- Per-platform golden/widget tests render key screens with `TargetPlatform.iOS`, `TargetPlatform.android`, and `TargetPlatform.windows`; no silent Material fallback. Accessibility semantics tested.

## Milestones / dependency order

1. Flutter workspace (`windows`, `android`, `ios` folders), pinned SDK, project identity, lint/test/Windows build and Android debug build in CI (#1).
2. Pure Dart domain plus table-driven tests and versioned SQLite repository (#2).
3. Add/edit/archive gear and log/edit/delete activities end to end (#3).
4. Wear dashboard and honest rotation view, notifications only in-app (#4).
5. Adaptive per-OS UI, keyboard/touch accessibility and golden/widget tests (#5).
6. Safe JSON backup/restore, CSV export, privacy and denial-path tests (#6).
7. Generated `AppStore/icon.png` wired to Windows/Android/iOS icons, listing-copy audit, Windows release workflow and downloadable zip (#7).

## Test strategy

- Pure Dart unit tests: unknown distance, zero/negative rejection, mi/km round trips, edits/deletions and archived-item history, nudge thresholds, month boundaries, timestamp timezone edge cases.
- SQLite migration and backup round-trip tests with fixtures; malformed import must leave existing DB untouched.
- Widget/golden tests at phone (390×844), tablet (1024×768), desktop (1440×900) with iOS/Android/Windows target platforms and textScale 1.0/2.0; keyboard traversal and semantics.
- Windows CI (`windows-latest`): `flutter analyze`, `flutter test`, `flutter build windows --release` with pinned Flutter. Linux Docker: `flutter test`, `flutter build apk --debug`. iOS build on macOS runner before mobile store submission; Linux structural checks alone do not prove an iOS build.
- Never claim a build/test result until command actually ran; initial repo is documentation-only.

## Packaging / distribution

- `.github/workflows/release.yml` on `v*` tag and manual dispatch builds Flutter Windows release on `windows-latest`, checks output, zips portable build and attaches artifact to a GitHub release. Optional MSIX only after store-signing requirements are understood.
- Android Play and iOS TestFlight later opt-in milestones. Four ASC secret names are provisioned now: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`; never log values. Apple bundle `com.infinityball.solemiles` still requires account-owner PLA acceptance and registration before TestFlight. Android uses same ID. Windows release is MVP deliverable.
- `AppStore/description.txt` describes planned behavior honestly; re-audit against implemented features before release. Generated `AppStore/icon.png` exists (OpenAI Images `gpt-image-2.5-flare`, 2026-10-31, 1024×1024 RGB); wire it to all platform icon sets in #7. No placeholder icons; icon brand color must not replace native OS UI conventions.

## Risks and non-goals

- Wear thresholds are user-configured heuristic maintenance targets, not physiological or medical advice. No diagnosis, treatment, or injury-prevention claims.
- Incorrect unit conversion can corrupt wear counts; store canonical integer meters, test display conversion at boundaries.
- Lost records on import are unacceptable; validate + pre-import snapshot + atomic transaction. No sync conflicts because no cloud.
- Offline by design: no network calls, login, social feed, GPS, step counting, wearable SDK, monetization, location permission, or cloud analytics.
- No native Swift/Xcode-only app, React Native, Expo, Kotlin Multiplatform, .NET MAUI, or Unity. Flutter app, not a game.
