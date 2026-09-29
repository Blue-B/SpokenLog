# Install SpokenLog

[Back to README](../README.md)

Download a package from the [latest release](https://github.com/Blue-B/SpokenLog/releases/latest) and follow the instructions for your platform.

## Known issues

Build 9 fixes local Whisper's 30-second truncation and adds Tiny, Base and Small selection. Long WAV files are transcribed in pieces. Whisper subtitle times are approximate, not word-accurate, and may need manual editing. Moonshine is no longer selectable; existing downloaded files are not deleted.

Synthetic-speech transcription passed with the final Windows release DLLs, the Android emulator release app, the macOS release app and an iPhone simulator build. These checks do not establish real-device microphone, background or interruption behavior. Some imported WAV details remained at “Checking duration” / `--:--` even though transcription succeeded. Some English-mode messages still appear in Korean.

See the [build details](releases/v0.1.0-build9-details.md) for the exact test scope, recording limits and remaining license-review gaps.

## Choose a package

| Platform | File | Installation |
| --- | --- | --- |
| Android 7.0+ | `SpokenLog-Android.apk` | Open the APK. If prompted, allow installation from the browser or file manager used to open it. |
| Windows x64 | `SpokenLog-Windows-x64-Setup.exe` | Run the per-user installer. It is not publisher-signed, so Windows may show a security warning. |
| Windows x64 portable | `SpokenLog-Windows-x64.zip` | Extract the entire ZIP into a new folder, then run `SpokenLog.exe`. Keep the accompanying files together. |
| macOS 12+ | `SpokenLog-macOS.zip` | Extract the ZIP and follow the Mac instructions below. |
| iOS / iPadOS 15+ | `SpokenLog-iOS-unsigned.ipa` | Requires signing and sideloading. Tapping the downloaded IPA does not install it. |

Only install files from a source you trust. `SHA256SUMS.txt` is provided to check download integrity. Back up important recordings and transcripts before replacing or removing an installation.

The Android APK currently uses a development signing key. Much older APKs signed with a different key may reject an in-place update. Do not uninstall just to work around that error without backing up your data.

## Mac installation

1. Download and extract `SpokenLog-macOS.zip`.
2. Move `SpokenLog.app` to Applications and try opening it.
3. If macOS blocks it because the developer cannot be verified, open **System Settings > Privacy & Security** and look for **Open Anyway** for SpokenLog. Approve only if you trust the downloaded copy.
4. Allow microphone access when you want to record.

The app is ad-hoc signed, not Apple-notarized. This manual installation route does not require a paid Apple developer account or weekly signing renewal. Do not disable Gatekeeper system-wide or bypass a malware warning. See [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

Build 9 was tested on a remote M2 Mac for app launch, Base selection and saving, native WAV import and 20-segment transcription. The CI machine needed an isolated, normally unlocked test Keychain. The full download-and-approval flow on an ordinary user's Mac remains unverified.

## iPhone and iPad installation

The supplied IPA is unsigned. It cannot be installed directly from Safari or Files. Free installation is possible through third-party tools using your own Apple Account, but it requires setup and ongoing signing renewal. This is a testing option, not a one-tap installation method for general users.

One option is [Sideloadly](https://sideloadly.io/):

1. Install Sideloadly on a Windows PC or Mac and follow its official setup instructions.
2. Connect your iPhone or iPad by USB and trust the computer when prompted.
3. Select `SpokenLog-iOS-unsigned.ipa` in Sideloadly and use your own Apple Account to sign and install it.
4. Follow the tool's instructions to trust your developer profile and enable Developer Mode if required by your iOS version.
5. Set up signing renewal. With a free account, the app normally expires after 7 days. Sideloadly can refresh it when its background helper is running on your computer and the device is reachable over USB or configured Wi-Fi.

[SideStore](https://docs.sidestore.io/docs/installation/install) allows on-device renewal after initial computer setup. It requires additional setup, including a local VPN app, and does not remove the 7-day limit. Device updates or pairing problems may require a computer again. Free accounts normally allow three active sideloaded apps; SideStore itself occupies one of those slots.

Use only the tools' official downloads and instructions. Do not send your Apple Account password to this project. Keep the same Apple Account and app identifier when updating, and export important recordings before troubleshooting. Deleting the app can delete its local recordings. See the [Sideloadly FAQ](https://sideloadly.io/faq.html) and [SideStore FAQ](https://docs.sidestore.io/docs/faq) for current requirements and limits.

These are documented installation routes, not completed SpokenLog device tests. Installation of this IPA through these tools, real iPhone recording and background behavior remain unverified.

## Removing the app

See [desktop removal and data management](desktop-removal.md). Back up important data first. Mobile uninstall, offload and reinstall do not all preserve data in the same way.

## Future store releases

We plan to publish SpokenLog on the Apple App Store and Google Play when funding and other release requirements allow. This includes production signing, real-device validation and the stores' review requirements. There is no announced release date, and store approval is not guaranteed.
