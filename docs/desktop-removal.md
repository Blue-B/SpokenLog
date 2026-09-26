# Desktop installation and data removal

These features are introduced in version 0.1.0 build 6. Data is kept by default.

## Windows

`SpokenLog-Windows-x64-Setup.exe` installs per-user under Local AppData, without administrator access, and registers a normal Windows uninstall entry. Removing it through Installed Apps opens SpokenLog's data screen before the installer removes program files. Recordings, downloaded models and credentials/preferences are separate opt-in categories. Nothing is selected by default. A second confirmation is required for permanent data deletion.

Cancel stops removal. Silent uninstall preserves all user data. The portable ZIP remains available, but deleting an extracted ZIP folder is not a managed uninstall. Portable users should open Settings → Storage management before removing the program files.

Build with Inno Setup 6 after a native release build (including app-local Microsoft runtime DLLs):

```powershell
powershell -NoProfile -File tool/package_windows.ps1 `
  -ReleaseDir build/windows/x64/runner/Release `
  -OutputDir dist/windows
```

The script checks executable/source versions and required DLLs. It produces the ZIP and installer from the same staged directory. Output paths must not already contain those packages.

## macOS

The ZIP includes `Uninstall-SpokenLog.command`. Keep it beside `SpokenLog.app`, or install the app at `/Applications/SpokenLog.app`. Quit SpokenLog before running the helper. It verifies the bundle identity, opens the same opt-in data screen, and moves only the identified app to Trash after successful completion. Cancellation or cleanup errors do not automatically remove the app. Gatekeeper/Finder may require user permission because distribution remains ad-hoc signed and not notarized.

Dragging the `.app` directly to Trash bypasses the helper and retains data. The helper cannot intercept Finder deletion, clean other macOS users' data, or run after the app has already been removed.

## Safety and scope

- Normal desktop launches and the cleanup process share a file lock. A second instance does not run cleanup against a current recording/transcription. Close older app versions too; versions before this change do not participate in the lock.
- In-app cleanup is blocked while recording, importing or transcribing; playback is stopped before opening the screen.
- The app resolves its own Documents/recordings and Application Support/models paths. The parent Documents and Application Support directories are never removed.
- The recordings choice deletes every file within that displayed recordings folder, including transcripts, collections and Trash. Back up important audio first.
- Linked root data directories are rejected. Size scans do not follow symbolic links. Partial model downloads are included in model cleanup.
- Exported recordings, externally imported originals, OS/cloud backups and API keys issued at the provider are not removed. Removing local credentials is not revoking the remote API key.
- The small instance lock and OS-specific preference/container metadata may remain. This is targeted application-data cleanup, not secure disk erasure.

## Verification scope

Dart regression tests cover opt-in defaults, cancellation, selective deletion and preservation of unrelated files using temporary fixtures. A native Windows preview passed installation and silent keep-data uninstallation; all 13 existing recording files remained unchanged. The cleanup screen and its keep-data button were also exercised on Windows.

The complete interactive installer cancellation/deletion flow and the macOS helper's Gatekeeper, sandbox and Finder behavior still need isolated runtime testing. Never point destructive tests at real recordings. Native builds and archive checks do not establish those runtime behaviors.
