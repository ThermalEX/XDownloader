# Repository Guidelines

## Structure

Work in `client/`. `lib/core/` contains platform-independent models and parsing; `lib/data/` owns repositories and durable snapshots; `lib/platform/` defines injected Android contracts; `lib/features/` contains Material 3 screens. Android storage, background downloads and APK installation live under `android/`. Offline tests are in `test/`, device tests in `integration_test/`.

## Development

Read [BUILDING.md](BUILDING.md). Run `dart format`, `flutter --no-version-check analyze` and `flutter --no-version-check test`. Use the production flavor for release builds and probe flavor for isolated device tests. Always select a device serial and use `--no-uninstall`; never clear production data for testing.

## Conventions

Follow `flutter_lints`, `snake_case.dart`, `PascalCase` types and `camelCase` members. Repositories own state; widgets do not edit snapshots or native download records. Keep platform-independent code free of Android imports. Use existing ColorScheme/TextTheme, rounded Material components, safe areas and 48dp touch targets. Verify light/dark themes, 320dp width and doubled text.

## Testing and commits

Add focused `*_test.dart` regressions for behavior changes. Inject HTTP and platform contracts; keep live-service checks separate. Verify cancellation, restart recovery, privacy and failed storage writes. Use focused Conventional Commits and describe behavior and validation in pull requests.

## Releases and private files

Never commit keys, passwords, device screenshots, logs or APKs to source control. Publish reviewed APKs as GitHub Release assets, preserving existing signatures and version ordering. Stable and Beta builds share increasing versionCode values. Keep probe fixtures out of production and never merge private development history into this public baseline.
