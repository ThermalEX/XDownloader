# Build and test

Use Flutter 3.47.7 (Dart 3.13.5), JDK 17 and Android SDK 36 with build-tools 36.0.0. Set `JAVA_HOME` and `ANDROID_HOME` for your machine. Flutter prepares generated platform files when required.

Copy `client/android/key.properties.example` to `client/android/key.properties`, configure your own local signing key and keep both out of Git. You need your own key to build; the official signing key is not published. A differently signed build cannot update an installed official APK.

From `client/`:

```powershell
flutter --no-version-check pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter --no-version-check analyze
flutter --no-version-check test
flutter --no-version-check build apk --release --flavor production --target-platform android-arm64
```

The APK appears in `client/build/app/outputs/flutter-apk/app-production-release.apk`. Save it outside the repository root before building the universal variant without `--target-platform`. Keep one versionCode for both variants; do not use `--split-per-abi` for this release pipeline.

Device tests use the isolated `com.xdl.app.probe` package:

```powershell
flutter --no-version-check test integration_test/app_flow_test.dart -d SERIAL --flavor probe --no-uninstall
```

Native update tests additionally need generated probe-only APK fixtures. Run `python tool/build_update_probe_fixtures.py --help`, generate them into an ignored directory, copy `fixtures.json` to `android/app/src/probe/assets/update_probe_fixtures.json`, and run `integration_test/app_updates_test.dart`. These fixtures and probe methods must be absent from production.

The update protocol uses `update.json` and `SHA256SUMS.txt` attached to each GitHub Release. Build both APKs with the same version and signing certificate, then use `tools/make_update_manifest.py --help` to generate matching metadata. Stable releases must not be marked prerelease; Beta tags use `vX.Y.Z-beta.N` and GitHub prerelease. All channels share a strictly increasing Android versionCode.

Update `client/assets/CHANGELOG.md` with each release so the offline changelog matches the installed version. It shares the themed Markdown renderer with downloaded release notes; embedded images are not loaded. Keep the changelog in the reviewed public-file inventory when exporting sources.

Pass `--changelog client/assets/CHANGELOG.md` to `tools/make_update_manifest.py` to generate `RELEASE_NOTES.md` without a duplicate version heading. Use `XDownloader X.Y.Z` as the GitHub Release title and the generated file as `--notes-file`. The app reads GitHub's `name` as its update title and renders only the description below it; offline changelog version headings remain intact.

## App icon

The transparent source is `client/assets/branding/app_icon.png`. From `client/`, run `dart run flutter_launcher_icons` to regenerate the Android launcher and adaptive foreground densities using the pinned development tool. Keep artwork alpha, the white adaptive background and the configured inset; this tool is not an application runtime dependency.
