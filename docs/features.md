# Features and supported formats

[Back to README](../README.md) | [Installation and known issues](installation.md)

## Recording library

Record audio directly or import an existing file. Recordings and transcripts stay together in the library, where you can rename items, organize collections, mark favorites, search transcript text, browse by calendar and recover deleted items from Trash.

- Start, pause, resume and stop recording.
- New recordings use a single 16 kHz mono WAV file.
- Review audio with a waveform, seeking and playback speed controls.
- Click a transcript timestamp to seek to that point.
- Edit transcript text and speaker names, then copy or export the result.
- Import several files and process selected recordings sequentially.

Active recordings periodically checkpoint metadata. Interrupted WAV sessions are recovered on the next launch when possible; this is not a substitute for backups.

There is no app-imposed recording timer, but recording is not unlimited. At 16 kHz mono 16-bit PCM, audio uses about 115 MB per hour. Conventional WAV's roughly 4 GB size limit corresponds to about 37 hours per file; this is a format ceiling, not a tested recording guarantee. Free space, battery, OS interruptions and memory can limit usable duration much earlier. Local transcription still loads the whole WAV into memory. A near-one-hour synthetic file was transcribed successfully, but continuous microphone recording for that duration was not tested.

## Imported files

| Format | Local transcription | Cloud transcription |
| --- | --- | --- |
| WAV | Supported input | Supported input |
| M4A / MP3 / MP4 / WebM | Not yet | Supported, subject to upload limits |

Large non-WAV files above the current cloud upload chunk limit are not automatically split. Large WAV cloud uploads use temporary WAV chunks that are cleaned up afterward. The original recording remains one file.

Imported files are copied into the library. The original file is not modified or moved. Format support does not imply every engine and device combination has passed runtime validation; check the [known issues](installation.md#known-issues).

## Transcription engines

| Engine | Where it runs | Notes |
| --- | --- | --- |
| SenseVoiceSmall INT8 | On your device | Korean, English, Chinese, Japanese and Cantonese; includes timestamps. About 239 MB. See the [Windows fix and testing limits](installation.md#known-issues). |
| Whisper Multilingual INT8 (Tiny, Base or Small) | On your device | 99 languages except Cantonese. Choose the size in settings: Tiny about 104 MB (fastest), Base about 161 MB, Small about 375 MB (larger model; accuracy still depends on the audio). The published models give no word times, so subtitle lines come from pauses in the audio (see [Export formats](#export-formats)). |
| Groq | Cloud | Whisper Large V3 or Large V3 Turbo, using your own API key. |
| Cloudflare Workers AI | Cloud | Whisper Large V3 Turbo, using your own credentials. |

Local models are downloaded separately. Local transcription has no service usage quota, and the app does not require a subscription. Optional cloud providers have their own limits and terms. OpenAI's paid API is not included as a default provider.

The app can fall back to another usable engine after a recoverable provider error. That does not protect against native process crashes.

## Languages

Interface language and transcription language are separate settings.

The interface has English and Korean display settings. Build 8 expands the English settings and playback translations; some errors and less-used paths can still show Korean. There is no Japanese interface in the current release.

Transcription offers automatic detection and these language selections:

- Korean, English, Japanese, Chinese and Cantonese
- Spanish, French, German, Portuguese, Italian, Russian and Polish
- Arabic, Hindi, Vietnamese, Ukrainian, Indonesian, Thai, Turkish and Dutch

Available languages depend on the engine. Unsupported engine choices are disabled. Whisper does not support the Cantonese selection.

## Local speaker diarization

Speaker diarization separates speakers in a recording. It runs locally after transcription, independently of the transcription provider, using sherpa-onnx with pyannote segmentation and 3D-Speaker embeddings.

It requires WAV input and about 42 MB of additional models. The speaker count can be automatic or set manually from 2 to 8. Audio is not uploaded for diarization.

It works with timestamped results from Groq, Cloudflare, SenseVoice and Local Whisper.

Labels such as `Speaker 1` and `Speaker 2` distinguish voices within a recording. They do not identify a person's real-world identity. You can rename the speakers afterward.

## Export formats

| Format | Contents |
| --- | --- |
| TXT | Readable text with timestamps and speaker labels when segments exist |
| SRT | Subtitle timestamps with speaker labels |
| VTT | WebVTT subtitles |
| JSON | Structured transcript and segment metadata |

Subtitle lines follow each engine's segments. SenseVoice, Groq and Cloudflare provide word or segment times. Local Whisper has no word times, so the app cuts the audio at pauses, transcribes each piece separately and uses the piece's start and end as the subtitle time; long recordings are handled this way too, because Whisper reads only the first 30 seconds of what it is given. There is no character-per-line or reading-speed adjustment, so broadcast subtitle rules may need manual work.

## Model licenses

Models are downloaded on request and are not bundled in the app.

| Model | License |
| --- | --- |
| Whisper (OpenAI) | MIT |
| SenseVoiceSmall | FunASR Model Open Source License 1.1: use, copy, modify and share are allowed; the source and author must be credited and the model name kept |
| pyannote segmentation 3.0 | MIT |
| 3D-Speaker ERes2Net embedding | Apache-2.0 in the 3D-Speaker project and ModelScope model metadata |

Whisper's MIT notice and the FunASR model license text are available in Settings → About → Open-source licenses. The app's AGPL-3.0-only license does not replace the model licenses. See the [build 9 license-review limits](releases/v0.1.0-build9-details.md#license-review) before treating this as clearance for commercial redistribution.

Earlier builds also offered Moonshine Tiny KO. Moonshine's non-English models use a community license that is free for research, non-commercial use and organizations under US$1 million annual revenue, with a separate commercial license required above that, so it was removed to keep the app clear of those conditions.

## Cloud usage display

### Groq

SpokenLog tracks successful audio duration used through this app and captures request-quota headers when Groq returns them.

Groq does not expose the account's exact remaining ASH/ASD audio quota in transcription response headers. Usage from other apps, devices or older versions is also outside the app's local counter. The app therefore cannot give an authoritative remaining audio quota. For that, use Groq Console > Settings > Limits.

### Cloudflare

SpokenLog estimates the Workers AI usage generated by this app using the published Whisper Large V3 Turbo neuron rate. The Workers AI daily quota is shared with other models and apps, which SpokenLog cannot see.

## Layout and platforms

- Phones below 600 px use stacked controls, compact recording menus and near-full-screen settings.
- Tablets and compact desktops use two-row controls with the active engine visible.
- Desktops use a library/detail layout and support file drag-and-drop. Mobile uses the native file picker.

Current packages target Windows x64, Android, macOS and iOS. Windows and Android are the first-release targets. macOS is ad-hoc signed; iOS requires re-signing. Linux and Web are not current release targets. See [installation](installation.md) and the [release notes](releases/v0.1.0.md) for platform-specific validation limits.

## Storage and privacy

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

API credentials are stored in OS secure storage. Local transcription and local speaker diarization do not send recordings to an external transcription service. Cloud transcription uploads audio when you explicitly start transcription with a cloud engine.

See [desktop data management](desktop-removal.md) for storage locations and removal options.
