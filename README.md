# SpokenLog

Record audio or import a file, transcribe it locally or with your own cloud credentials, then edit and export the transcript.

https://github.com/user-attachments/assets/cf12c70e-a913-4209-887f-9ed36139ffa6

## Download

Download the [latest release](https://github.com/Blue-B/SpokenLog/releases/latest) for your platform. Back up important recordings before updating.

| Platform | Download | Note |
| --- | --- | --- |
| Android 7.0+ | [APK](https://github.com/Blue-B/SpokenLog/releases/latest/download/SpokenLog-Android.apk) | Development-signed |
| Windows x64 | [Setup.exe (recommended)](https://github.com/Blue-B/SpokenLog/releases/latest/download/SpokenLog-Windows-x64-Setup.exe) / [ZIP (no install)](https://github.com/Blue-B/SpokenLog/releases/latest/download/SpokenLog-Windows-x64.zip) | Unsigned |
| macOS 12+ | [ZIP](https://github.com/Blue-B/SpokenLog/releases/latest/download/SpokenLog-macOS.zip) | Not notarized |
| iOS / iPadOS 15+ | [Unsigned IPA](https://github.com/Blue-B/SpokenLog/releases/latest/download/SpokenLog-iOS-unsigned.ipa) | Re-signing required; not tap-to-install |

These are direct-download builds, not App Store or Google Play releases. Follow the [installation guide](docs/installation.md) for your platform.

[Checksums](https://github.com/Blue-B/SpokenLog/releases/latest/download/SHA256SUMS.txt) | [Release notes, known issues and verification scope](https://github.com/Blue-B/SpokenLog/releases/latest)

## Features

- Recording library with search, collections, favorites and timestamped playback.
- Local SenseVoice or Whisper (Tiny, Base or Small); cloud transcription with your own Groq or Cloudflare credentials.
- Transcript editing, local speaker labels, and TXT, SRT, VTT or JSON export.

Local transcription keeps audio on your device and currently requires WAV. Cloud transcription uploads audio to the selected provider. The interface supports English and Korean; spoken-language support depends on the engine.

## Documentation

[Features and formats](docs/features.md) | [Build from source](docs/development.md) | [Data management and removal](docs/desktop-removal.md) | [Release history](https://github.com/Blue-B/SpokenLog/releases)

[AGPL-3.0-only](LICENSE) | [Branding policy](TRADEMARKS.md)
