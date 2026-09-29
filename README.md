# SpokenLog

Record audio or import a file, transcribe it, and export the text.

https://github.com/user-attachments/assets/cf12c70e-a913-4209-887f-9ed36139ffa6

## Download

| Platform | Download | Note |
| --- | --- | --- |
| Android 7.0+ | [APK](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.0/SpokenLog-Android.apk) | Development-signed |
| Windows x64 | [Setup.exe (recommended)](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.0/SpokenLog-Windows-x64-Setup.exe) / [ZIP (no install)](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.0/SpokenLog-Windows-x64.zip) | Unsigned |
| macOS 12+ | [ZIP](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.0/SpokenLog-macOS.zip) | Not notarized |
| iOS / iPadOS 15+ | [Unsigned IPA](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.0/SpokenLog-iOS-unsigned.ipa) | Re-signing required; not tap-to-install |

Current packages: **0.1.0, build 9**. Back up important recordings before updating. [Installation guide](docs/installation.md) | [Checksums](https://github.com/Blue-B/SpokenLog/releases/download/v0.1.0/SHA256SUMS.txt) | [Tested behavior and limits](docs/releases/v0.1.0-build9-details.md)

## Features

- Recording library with search, collections, favorites and timestamped playback.
- Local SenseVoice or Whisper (Tiny, Base or Small); cloud transcription with your own Groq or Cloudflare credentials.
- Transcript editing, local speaker labels, and TXT, SRT, VTT or JSON export.

Local transcription keeps audio on your device and currently requires WAV. Cloud transcription uploads audio to the selected provider. The interface supports English and Korean; spoken-language support depends on the engine.

## Documentation

[Features and formats](docs/features.md) | [Build from source](docs/development.md) | [Data management and removal](docs/desktop-removal.md) | [Release notes](docs/releases/v0.1.0.md)

[AGPL-3.0-only](LICENSE) | [Branding policy](TRADEMARKS.md)
