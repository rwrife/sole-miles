# Sole Miles

Offline shoe and gear mileage tracker: log runs and walks, track shoe wear against retire targets, rotate pairs, and catch worn-out soles on phone, tablet, and Windows without accounts.

- **Repo:** https://github.com/rwrife/sole-miles
- **App identifier:** `com.infinityball.solemiles` (Android applicationId, iOS bundle identifier, Windows identity `cominfinityball.solemiles`)

## Manual setup required

- **App Store Connect bundle ID not registered.** `python3 asc_create_bundle_id.py sole-miles` failed with
  `FAILED bundleId lookup rejected: FORBIDDEN_ERROR.PLA_NOT_ACCEPTED` (2026-10-31).
  The account owner must accept the current Apple Developer Program License Agreement in
  the developer portal, then register `com.infinityball.solemiles` in App Store Connect
  (Credentials > Identifiers) manually or by re-running the script. Credential values are
  never stored in this repository.

## Overview

Sole Miles is a local-first mileage ledger for the gear you wear out: running shoes,
walking shoes, trail shoes, racing flats, and any mileage-limited sports gear
(basketball shoes, hiking boots, climbing shoes, padel rackets' strings if you track
them). You record an activity once — distance, activity type, how it felt — and pick
which pair you wore. The app keeps honest per-item mileage, warns as an item
approaches its retire-by distance, and shows you whether your rotation is actually
rotating.

**Pitch:** A runner or walker who owns 2–5 pairs of shoes finally knows which pair is at
380 of a 500 km life, which pair has been sitting for a month, and when to buy the next
pair — offline, on phone, tablet, or Windows, with no account.

## Motivation

Most runners replace shoes by guesswork. Cushioning degrades long before the outsole
looks worn, and the common "500 km / 300 mi" rule is impossible to apply unless you
log the distance of every run per shoe. Existing mileage apps are social networks
(Strava) or step-count gamification (WalkFit) — they either require an account and
cloud or count steps instead of tracking the gear itself. People who rotate pairs to
extend total shoe life have no simple tool to see per-pair wear and rotation balance.

## Target users

- Runners and walkers with 1–5 pairs of shoes who want replace-by honesty, not a social feed.
- Parents tracking kids' quickly-worn-out sneakers and sports shoes.
- Hikers, basketball players, climbers, and other recreation athletes whose gear has a usable-life mileage.
- Anyone who wants their activity-and-gear history to stay on their own device.

## Use cases

1. **Log a run in five seconds:** open the app, tap "Log activity", confirm distance and duration (or type them), pick the pair you wore, save.
2. **Wear dashboard:** each pair shows odometer, percent of retire target, last-used date, and a wear trend line.
3. **Rotation check:** see miles per pair over the last 4 weeks side by side; spot the pair you keep skipping.
4. **Retire nudge:** a banner appears at 85 % of a pair's retire target and a firm notice at 100 %, with a one-tap "retire and replace" flow that archives history and links the successor pair.
5. **Gear beyond shoes:** add basketball shoes or hiking boots with a distance-based retire target. Time- or session-based gear tracking is deferred.

## How to use (intended workflow)

1. Add your gear: name, brand/model (free text), optional photo, unit (km or miles), activity type, retire target (sensible defaults per activity, fully editable).
2. Log activities: date, activity type, distance (or duration for time-based gear), which item you wore, optional feel note.
3. Watch odometers. The item list sorts by wear percent; the item detail shows mileage history per month.
4. When an item hits its retire target, retire it in one tap. History stays browsable; the replacement inherits nothing by default but you can copy settings.
5. Export or back up everything as JSON (full fidelity) or CSV (activities, per-item totals) whenever you like. Restore from the JSON backup.

## MVP feature list

- Gear items with custom retire targets, units (km/mi), activity categories, optional photos.
- Activity log (walk, run, trail run, hike, court, gym, custom type) with per-activity item assignment; an activity can wear at most one item per category.
- Deterministic mileage math: odometer = sum of assigned distances; unknown distances can be recorded as "unknown" and are excluded from odometers, never guessed.
- Wear states: healthy, nudge (≥ 85 %), retire (≥ 100 %), retired (archived, history kept).
- Rotation view: last-4-weeks miles per active pair, last-used dates.
- Local SQLite storage, JSON backup/restore, CSV export. Zero network requests.
- Platform-authentic adaptive UI (see PLAN.md): phone, tablet, desktop window sizes; touch + keyboard/mouse.

## Non-goals

- No accounts, cloud sync, social feed, leaderboards, or ads.
- No GPS tracking — distances come from the user (typed, or copied from a watch/phone app they already use). No Health Kit / Google Fit integration in MVP; a documented import issue may follow.
- No step counting, no wearable SDKs, no Bluetooth devices.
- No medical or injury advice. Sole Miles is a mileage ledger; it makes no diagnosis, treatment, or pain-safety claims. "Retire target" is a user-editable maintenance heuristic, not medical guidance.
- No purchase price, store, or marketplace features.
- No Flutter-for-games, and this project uses no other framework: no native Swift/Xcode-only app, no React Native, no Expo, no Kotlin Multiplatform, no .NET MAUI, no Unity — Flutter only, per fleet policy.

## Privacy, permissions, and data storage

- **All data is local.** SQLite database in the app's private storage plus user-triggered
  backup files chosen through native OS save dialogs. The app performs no network requests.
- **Permissions:** camera/photo picker only, and only when the user adds an item photo
  (system photo-library access where the platform requires it). No location, no contacts,
  no microphone, no notifications by default (retire nudges are in-app; OS notifications
  are a later opt-in issue at most).
- **No identifiers collected.** No account, no analytics, no ad SDKs, no crash-reporting
  upload. Export files contain only what the user logged.
- Photos are copied into app storage so gallery deletions don't break records; backups
  include photos only when the user checks that option.

## Current status

Flutter workspace and PR CI scaffolded for Windows, Android, and iOS. The app
currently shows only a neutral title screen; mileage flows, adaptive OS UI,
and icon wiring remain issues #2–#7. `AppStore/icon.png` exists but is not
wired to platform icons yet. See `PLAN.md` for architecture and milestones.

## Development quickstart (target)

Pinned toolchain in `toolchain.json` (Flutter 3.47.2, Dart 3.13.2).

```sh
flutter --version            # verify toolchain.json pin
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build windows --release # Windows host
flutter build apk --debug     # Android SDK host
```

Windows is the primary CI/release target (`windows-latest`); Android/iOS (phones and
tablets) must keep compiling. See `PLAN.md`.

## CI and packaging

- Release Action `.github/workflows/release.yml` (issue #7): `v*` tag or manual dispatch →
  `windows-latest` → `flutter build windows --release` → zipped portable build attached to
  a GitHub release. iOS TestFlight later uses the four repository secrets named
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (values never logged).
- App icon: `AppStore/icon.png` (generated, see above) will replace scaffold icons in
  Windows, Android, and iOS under issue #7.
- Adaptive UI seam symbols: `AdaptiveScaffold`, `AdaptiveButton`, `AdaptiveDialog` (Cupertino on iOS, Material 3 on Android, Fluent on Windows — UX strategy A, see PLAN.md).

## License

MIT — see `LICENSE`.
