# SpokenLog

**Record it. Know what was said.**

SpokenLog is a local-first, cloud-optional recorder and transcription app. The name is literal: a log of spoken words, not the name of a speech model or AI technology. Record directly, drop in an existing audio/video file, switch between local and cloud STT, add speaker labels locally, and export the result without being locked to one transcription engine.

![SpokenLog workflow](docs/spokenlog-workflow.svg)

> First release: **[v0.1.0](https://github.com/Blue-B/SpokenLog/releases/tag/v0.1.0)**. The replacement Android and iOS packages remain version 0.1.0 (internal build 3). Android's launcher package is corrected; the iOS IPA remains unsigned and requires Apple signing before installation. See the [release notes](docs/releases/v0.1.0.md) for verification results and Android update-signing precautions.

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

- **Windows** — packaged x64 release ZIP with CI build validation.
- **Android** — packaged release APK with microphone foreground-recording integration.
- **macOS** — packaged release app ZIP built on macOS CI. The GitHub build is ad-hoc signed rather than Apple-notarized.
- **iOS** — device release is compiled as an unsigned IPA. Apple requires re-signing with a valid developer certificate/provisioning profile before it can be installed on a physical device.
- **Linux / Web** — not current release targets.

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
