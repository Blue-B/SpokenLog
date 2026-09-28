# Build and validate SpokenLog

[Back to README](../README.md)

Use Flutter stable. The local setup was tested with Flutter 3.47.5. Android builds require an Android SDK and JDK; Windows builds require Windows and Visual Studio's desktop C++ tools. Check installed toolchains with `flutter doctor`.

## Local setup

Native runners are generated rather than stored in full. The custom `android/app/src/main/AndroidManifest.xml` is kept in the repository because microphone foreground recording needs app-level service declarations.

From a clean checkout, generate the missing runner files before building:

```text
flutter create --no-pub --empty --platforms=android,windows --project-name spokenlog --org io.github.blueb .
git restore -- pubspec.lock
flutter pub get --enforce-lockfile
dart run flutter_launcher_icons
```

Do not add `--overwrite`: existing app files and the custom Android manifest must be preserved. `--empty` avoids generating Flutter's unrelated counter-app test. Runner creation can replace `pubspec.lock` even with `--no-pub`, so the next command restores the checked-in dependency versions. Do not use that restore command if you have intentional local lockfile changes; back them up first.

Then validate the shared code and build for the available host toolchain:

```text
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release
```

On Windows, also run `flutter build windows --release`. CI additionally applies the Windows executable/window branding. Generated runner files and build output are ignored; keep `pubspec.lock` and the custom Android manifest in version control.

## CI and device checks

GitHub Actions analyzes and tests the shared code and builds Windows ZIP and Android APK artifacts. It does not create the Windows installer or publish releases. Runner generation restores the checked-in lockfile before dependency resolution.

For release packaging, use `tool/package_windows.ps1` on Windows and the manual `apple-release` workflow in `codemagic.yaml` for macOS and unsigned iOS. Verify all packages and checksums before uploading them. The older GitHub Actions publishing path has been removed.

Hosted builds require available GitHub Actions budget. The current release used local Windows/Android builds and remote Apple builds; see the [build details](releases/v0.1.0-build8-details.md) for provenance. Before store distribution, configure persistent production signing. The current Android build uses development signing.

Compilation does not replace real-device checks. Before store distribution, test Android recording, pause/resume, screen-off recording, stopping, permission denial and interrupted-session recovery on current devices. macOS should also be tested on physical Apple hardware. The unsigned iOS asset is intended for re-signing and testing until official Apple signing is configured.

Check the [known issues](installation.md#known-issues) as well as the release notes. Later runtime findings can reveal problems that compilation and unit tests did not detect.
