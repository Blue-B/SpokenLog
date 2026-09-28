# Install SpokenLog

[Back to README](../README.md)

The current release is [v0.1.0, build 7](https://github.com/Blue-B/SpokenLog/releases/tag/v0.1.0). These are direct-download test packages, not App Store, Google Play or TestFlight releases. While the repository is private, downloads require repository access. Sharing the release URL does not grant access.

## Known issues

The published Windows build 7 can crash when local SenseVoice loads an incompatible system ONNX Runtime instead of the bundled version. An unreleased local build fixes the load order by opening the bundled runtime first. The synthetic WAV completed transcription in that build, including during the demo. The published downloads have not been replaced. Other engines and platforms have not received equivalent inference testing.

The published build still has some Korean labels in English mode. The unreleased demo build translates the settings and playback messages found during testing and uses a single Settings entry. Not every error path has been checked. Japanese is a transcription language, not an interface language.

See the [release notes](releases/v0.1.0.md) for earlier checks and their limits. The findings above were made after those release notes were published.

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

The release ZIP was tested on a remote Mac for file import and restart. The full download-and-approval flow on an ordinary user's Mac remains unverified.

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
