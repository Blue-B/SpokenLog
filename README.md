# SpokenLog

**Record it. Know what was said.**

SpokenLog is a local-first, cloud-optional recorder and transcription app. The name is literal: a log of spoken words, not the name of a speech model or AI technology. Record directly, drop in an existing audio/video file, switch between local and cloud STT, add speaker labels locally, and export the result without being locked to one transcription engine.

![SpokenLog workflow](docs/spokenlog-workflow.svg)

> Current release: **[v0.1.0, build 7](https://github.com/Blue-B/SpokenLog/releases/tag/v0.1.0)** for Android, Windows, macOS and iOS. The displayed version remains 0.1.0. Read the installation instructions below before downloading, especially on iPhone and iPad. See the [release notes](docs/releases/v0.1.0.md) for verified behavior and remaining test coverage.

## Download and install

Download files from the release linked above. While this repository is private, downloading requires repository access; sharing the release URL alone does not give others access. These are direct-download test packages, not App Store, Google Play or TestFlight releases.

| Platform | File | Installation |
| --- | --- | --- |
| Android | `SpokenLog-Android.apk` | Open the APK and, if prompted, allow installation from the browser or file manager used to open it. Android 7.0 or later. |
| Windows x64 | `SpokenLog-Windows-x64-Setup.exe` | Run the per-user installer. It is not publisher-signed, so Windows may show a security warning. |
| Windows x64 portable | `SpokenLog-Windows-x64.zip` | Extract the entire ZIP into a new folder, then run `SpokenLog.exe`. Keep the accompanying files together. |
| macOS | `SpokenLog-macOS.zip` | Extract the ZIP and follow the Mac instructions below. macOS 12 or later. |
| iPhone / iPad | `SpokenLog-iOS-unsigned.ipa` | Requires signing and sideloading; tapping the downloaded IPA does not install it. iOS / iPadOS 15 or later. |

Only install files from a source you trust. `SHA256SUMS.txt` is provided to check download integrity. Back up important recordings and transcripts before replacing or removing an existing installation. The Android APK currently uses a development signing key; much older APKs signed with a different key may reject an in-place update. Do not uninstall just to work around that error without backing up your data.

### Mac installation

1. Download and extract `SpokenLog-macOS.zip`.
2. Move `SpokenLog.app` to Applications and try opening it.
3. If macOS blocks it because the developer cannot be verified, open **System Settings > Privacy & Security** and look for **Open Anyway** for SpokenLog. Approve only if you trust the downloaded copy.
4. Allow microphone access when you want to record.

The app is ad-hoc signed, not Apple-notarized. This manual installation route does not require a paid Apple developer account or weekly signing renewal. Do not disable Gatekeeper system-wide or bypass a malware warning. See [Apple's instructions for opening an app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

The release ZIP was tested on a remote Mac for file import and restart, but the full download-and-approval flow on an ordinary user's Mac remains unverified.

### iPhone and iPad installation

The supplied IPA is unsigned. It cannot be installed directly from Safari or Files. Free installation is possible through third-party tools using your own Apple Account, but it requires setup and ongoing signing renewal. This is a testing option, not a one-tap installation method for general users.

One option is [Sideloadly](https://sideloadly.io/):

1. Install Sideloadly on a Windows PC or Mac and follow its official setup instructions.
2. Connect your iPhone or iPad by USB and trust the computer when prompted.
3. Select `SpokenLog-iOS-unsigned.ipa` in Sideloadly and use your own Apple Account to sign and install it.
4. Follow the tool's instructions to trust your developer profile and enable Developer Mode if required by your iOS version.
5. Set up signing renewal. With a free account, the app normally expires after 7 days. Sideloadly can refresh it when its background helper is running on your computer and the device is reachable over USB or configured Wi-Fi.

[SideStore](https://docs.sidestore.io/docs/installation/install) is an alternative that allows on-device renewal after initial computer setup. It requires additional setup, including a local VPN app, and does not remove the 7-day limit. Device updates or pairing problems may require a computer again. Free accounts normally allow three active sideloaded apps; SideStore itself occupies one of those slots.

Use only the tools' official downloads and instructions. Do not send your Apple Account password to this project. Keep the same Apple Account and app identifier when updating, and export important recordings before troubleshooting. Deleting the app can delete its local recordings. See the [Sideloadly FAQ](https://sideloadly.io/faq.html) and [SideStore FAQ](https://docs.sidestore.io/docs/faq) for current requirements and limits.

These are documented installation routes, not completed SpokenLog device tests. Installation of this IPA through these tools, real iPhone recording and background behavior remain unverified.

### Future store releases

We plan to publish SpokenLog on the Apple App Store and Google Play when funding and other release requirements allow. This includes production signing, real-device validation and the stores' review requirements. There is no announced release date, and store approval is not guaranteed. Until then, use the direct-download packages with the installation requirements and testing limits described above.

## What makes SpokenLog different

SpokenLog is built as a **recording library first, transcription tool second**. It is for people who want to keep everyday recordings organized and searchable without committing to one AI provider.

- **One library for recording and transcription** — record, import, rename, organize into collections, favorite, search transcript text, browse by calendar, and recover deleted items.
- **Native mobile direction** — Android is a first-class target rather than a phone remote for a desktop transcriber.
- **Choose per device and situation** — stay fully local when privacy matters, or use your own Groq / Cloudflare credentials when cloud speed is more useful.
- **Provider-independent speaker workflow** — local diarization can sit on top of supported local or cloud STT results, and speaker names plus transcript text remain editable afterward.
- **No fake quota meter** — when a provider does not expose authoritative remaining usage, SpokenLog says so instead of inventing a number.
- **Crash-aware recording storage** — active recordings checkpoint metadata periodically and interrupted WAV sessions are recovered on the next launch when possible.
- **Batch without parallel chaos** — import multiple files and process selected recordings through a sequential transcription queue.

If this workflow is useful to you, a GitHub star helps other people discover the project.

## Why SpokenLog

- **Local ↔ Cloud without lock-in** — switch between SenseVoice, Moonshine, local Whisper, Groq, and Cloudflare.
- **Speaker diarization stays local** — pyannote segmentation + 3D-Speaker embeddings run on-device as a provider-independent post-process.
- **Drag, drop, transcribe** — import WAV, M4A, MP3, MP4, or WebM instead of recording everything again.
- **Useful exports** — save speaker-aware transcripts as TXT, SRT, VTT, or JSON.
- **Usage visibility** — show what the app can reliably track for cloud free-tier usage and point users to the provider dashboard when exact remaining quota is unavailable.
- **No subscription required** — local transcription has no usage quota; cloud providers are optional.

## 10-second workflow

1. Record in SpokenLog or drag an existing file onto the app.
2. Choose **Local** for privacy/offline use or **Cloud** for speed and stronger large-model accuracy.
3. Optionally enable **Local speaker diarization**.
4. Click a timestamp to review the audio, correct transcript segments or speaker names, then copy or export TXT/SRT/VTT/JSON.

### Imported files

| Format | Local STT | Cloud STT |
| --- | --- | --- |
| WAV | Yes | Yes |
| M4A / MP3 / MP4 / WebM | Not yet | Yes* |

`* Large non-WAV files above the current cloud upload chunk limit are not automatically split yet.`

Imported files are copied into SpokenLog's library. The original file is not modified or moved.

## Transcription engines

### Cloud

- **Groq** — Whisper Large V3 / Large V3 Turbo. Fast multilingual cloud transcription.
- **Cloudflare Workers AI** — Whisper Large V3 Turbo. Separate Workers AI free-tier capacity.

### Local

- **SenseVoiceSmall INT8** — fast local transcription for Korean, English, Chinese, Japanese, and Cantonese; includes timestamps.
- **Moonshine Tiny KO** — ~69MB lightweight Korean-only local model.
- **Whisper Tiny Multilingual INT8** — ~104MB general multilingual local fallback.

OpenAI's paid API is not included as a default provider because the project is built around free-first and local-first usage.

## Local speaker diarization

Speaker diarization is separate from STT and runs locally after transcription.

- sherpa-onnx Offline Speaker Diarization
- pyannote segmentation + 3D-Speaker embedding + clustering
- ~42MB additional models
- automatic speaker count or manual 2–8 speaker selection
- audio is not uploaded for diarization
- diarization currently requires WAV input
- shared across Groq, Cloudflare, SenseVoice, and Local Whisper results with timestamped segments
- Moonshine currently has no detailed timestamp segments, so speaker labels are skipped for it

The labels identify `Speaker 1`, `Speaker 2`, etc. within the recording. They do not identify a person's real-world identity.

## Languages

The transcription language is selected independently from the engine.

Automatic detection plus Korean, English, Japanese, Chinese/Cantonese, Spanish, French, German, Portuguese, Italian, Russian, Arabic, Hindi, Vietnamese, Ukrainian, Indonesian, Thai, Turkish, Dutch, and Polish are available. Engines that do not support the selected language are disabled in settings.

## Platform support

- **Windows**: x64 installer and portable ZIP, built locally for the current release.
- **Android**: release APK with microphone foreground-recording integration and development signing.
- **macOS**: app ZIP built on a remote Mac, ad-hoc signed rather than Apple-notarized.
- **iOS**: unsigned device IPA for re-signing and testing, not direct installation or a store release.
- **Linux / Web**: not current release targets.

See [Download and install](#download-and-install) for setup instructions and limitations.

## Responsive UI

- **Phone (<600 px)** — stacked status header, full-width import/record actions, compact recording menus, wrapping transcript actions, near-full-screen settings.
- **Tablet / compact desktop** — two-row controls with the active engine still visible.
- **Desktop** — single-row toolbar, drag-and-drop import, and split library/detail workspace.
- File drag-and-drop is enabled only on desktop; mobile uses the native file picker.

## Recording and library

- Windows and Android are the current first-release targets
- start / pause / resume / stop recording
- new recordings stored as one 16 kHz mono WAV
- interactive WAV waveform
- playback, seek, and speed control
- timestamp click-to-seek
- desktop library/sidebar + detail workspace
- rename, transcript editing, custom speaker names, search, reveal file location, delete confirmation
- API credentials stored in OS secure storage
- local model download/delete management
- fallback to another usable engine when a provider hits a recoverable error

## Export formats

- **TXT** — readable timestamp + speaker labels when segments exist
- **SRT** — subtitle timestamps with speaker labels
- **VTT** — WebVTT subtitle output
- **JSON** — structured transcript and segment metadata

## Cloud usage display

### Groq

SpokenLog tracks successful audio duration used through this app and captures request-quota headers when Groq returns them.

Groq does not expose the account's exact remaining ASH/ASD audio quota in the transcription response headers, so SpokenLog does **not** pretend to know it. Usage from other apps, devices, or older versions is also outside the app's local counter. For the authoritative value, use **Groq Console → Settings → Limits**.

### Cloudflare

SpokenLog estimates the Workers AI usage generated by this app using the published Whisper Large V3 Turbo neuron rate. The Workers AI daily quota is shared with other Workers AI models and apps, which SpokenLog cannot see.

## Storage

```text
recordings/
  recording_20260919_183000/
    session.json
    recording.wav
    transcript.txt
    transcript.json

  import_20260920_120000_123456/
    session.json
    imported.mp3
    transcript.txt
    transcript.json
```

Large WAV cloud uploads are split only into temporary WAV chunks during transcription and cleaned up afterward. The original recording remains a single file.

## Build validation

Use Flutter stable (local setup tested with Flutter 3.47.5). Android builds require an Android SDK and JDK; Windows builds require Windows and Visual Studio's desktop C++ tools. Check the installed toolchains with `flutter doctor`.

### Local setup

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

### CI and device checks

GitHub Actions analyzes and tests the shared code and builds Windows and Android release artifacts. Runner generation restores the checked-in lockfile before dependency resolution. Manual workflow runs can additionally build macOS and unsigned iOS packages and replace assets on the requested release after every build succeeds. The requested release tag must match `pubspec.yaml`; publishing no longer depends on special commit messages and does not delete an existing release first. Hosted builds require available GitHub Actions budget. Before store distribution, configure persistent production signing; the current Android build uses development signing.

Compilation does not replace real-device checks. Before store distribution, test Android recording, pause/resume, screen-off recording, stopping, permission denial, and interrupted-session recovery on current devices. macOS should also be tested on physical Apple hardware. The iOS GitHub asset is unsigned and is intended for re-signing/testing until official Apple signing is configured.

## Security

- API keys are never committed to the source repository.
- Cloud transcription uploads audio only when the user explicitly starts transcription.
- Local STT and local speaker diarization do not send the recording to an external transcription service.


## License

SpokenLog is free and open-source software licensed under the **GNU Affero General Public License v3.0 only (AGPL-3.0-only)**.

You may use, study, modify, distribute, and use the software commercially under the terms of the AGPLv3. If you modify SpokenLog and make that modified version available to users over a network, the AGPL's network-source requirement applies: those users must be offered access to the corresponding source code for the version they are using.

See [LICENSE](LICENSE) for the complete license text.

The software license does not grant rights to present an unofficial fork or service as the official **SpokenLog** project. See [TRADEMARKS.md](TRADEMARKS.md) for the project branding policy.
