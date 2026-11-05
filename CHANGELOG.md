# Changelog

All notable changes to Sole Miles are documented in this file.

## [1.0.0+1] - 2026-11-05

### Added
- Offline shoe and sports-gear mileage ledger built with Flutter for Windows, Android, and iOS.
- Local SQLite persistence with deterministic odometers, wear state calculations, and nudge thresholds.
- Gear management: custom retire targets, distance units (km/mi), activity categories, and item archival.
- Activity logging: date, category, distance, feel notes, and per-activity pair assignment.
- Wear dashboard and 4-week rotation view.
- Local JSON backup and restore with pre-flight validation and CSV export for spreadsheets.
- Native adaptive UI: Fluent UI on Windows, Material 3 on Android, and Cupertino on iOS.
- Generated launcher icon (`AppStore/icon.png`) wired into Windows `.ico`, Android launcher mipmaps, and iOS AppIcon asset sets.
- Automated portable Windows release workflow (`.github/workflows/release.yml`) producing downloadable GitHub release zip artifacts.
