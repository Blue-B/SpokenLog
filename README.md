# SpokenLog

Record audio or import a file, transcribe it locally or with your own cloud credentials, then edit and export the transcript.

https://github.com/user-attachments/assets/cf12c70e-a913-4209-887f-9ed36139ffa6

## Download

Version **0.1.2, build 10** keeps the build 9 transcription improvements and adds safer local saves and bounded cloud requests. Back up important recordings before updating.

| Platform | Download | Note |
| --- | --- | --- |
| Android 7.0+ | [APK](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.2/SpokenLog-Android.apk) | Development-signed |
| Windows x64 | [Setup.exe (recommended)](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.2/SpokenLog-Windows-x64-Setup.exe) / [ZIP (no install)](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.2/SpokenLog-Windows-x64.zip) | Unsigned |
| macOS 12+ | [ZIP](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.2/SpokenLog-macOS.zip) | Not notarized |
| iOS / iPadOS 15+ | [Unsigned IPA](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.2/SpokenLog-iOS-unsigned.ipa) | Re-signing required; not tap-to-install |

[Installation guide](docs/installation.md) | [Checksums](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.2/SHA256SUMS.txt) | [Release notes and verification scope](docs/releases/v0.1.2.md)

## Features

- Recording library with search, collections, favorites and timestamped playback.
- Local SenseVoice or Whisper (Tiny, Base or Small); cloud transcription with your own Groq or Cloudflare credentials.
- Transcript editing, local speaker labels, and TXT, SRT, VTT or JSON export.

Local transcription keeps audio on your device and currently requires WAV. Cloud transcription uploads audio to the selected provider. The interface supports English and Korean; spoken-language support depends on the engine.

## Changes in 0.1.2

- Recording metadata is replaced through a staged file, and checkpoint writes finish in order before the final recording state is saved.
- Transcript text, segments and speaker labels are loaded from one JSON snapshot. Older TXT-only recordings still load; TXT is kept as a compatibility copy.
- Cloud requests have a 10-minute limit per audio part, covering upload and the full response. The connection is closed on completion or timeout.

## Documentation

[Features and formats](docs/features.md) | [Build from source](docs/development.md) | [Data management and removal](docs/desktop-removal.md) | [Release notes](docs/releases/v0.1.2.md)

[AGPL-3.0-only](LICENSE) | [Branding policy](TRADEMARKS.md)
