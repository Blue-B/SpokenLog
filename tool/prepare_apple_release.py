"""Configure generated Apple runners, or verify their release archives.

Called by codemagic.yaml after flutter create. No signing credentials are used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "io.github.blueb.spokenlog"
# Keep the existing direct-download app's Documents/Support and login Keychain.
# Enabling App Sandbox here would silently switch existing users to a container.
MACOS_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": False,
    "com.apple.security.device.audio-input": True,
    "com.apple.security.network.client": True,
    "com.apple.security.files.user-selected.read-write": True,
}


def app_version() -> tuple[str, str]:
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$",
                      (ROOT / "pubspec.yaml").read_text(), re.MULTILINE)
    if match is None:
        raise ValueError("Expected major.minor.patch+build in pubspec.yaml.")
    return match[1], match[2]


def update_plist(path: Path, changes: dict) -> None:
    data = plistlib.loads(path.read_bytes())
    data.update(changes)
    path.write_bytes(plistlib.dumps(data, sort_keys=False))


def prepare() -> None:
    app_version()
    config = ROOT / "macos/Runner/Configs/AppInfo.xcconfig"
    text = config.read_text()
    for key, value in {"PRODUCT_NAME": "SpokenLog",
                       "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID}.items():
        text, count = re.subn(rf"^{key}\s*=.*$", f"{key} = {value}",
                             text, flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f"Expected one {key} entry in generated runner")
    config.write_text(text)
    microphone = "SpokenLog needs microphone access to record audio."
    # MetalSDF produced corrupted glyphs on the remote M2 after app restarts.
    # Use Flutter's supported macOS renderer opt-out, without changing iOS.
    update_plist(ROOT / "macos/Runner/Info.plist",
                 {"NSMicrophoneUsageDescription": microphone,
                  "FLTEnableImpeller": False})
    for name in ("DebugProfile.entitlements", "Release.entitlements"):
        update_plist(ROOT / "macos/Runner" / name, MACOS_ENTITLEMENTS)
    project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()
    if f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};" not in project:
        raise ValueError("Unexpected generated iOS bundle identifier")
    info = ROOT / "ios/Runner/Info.plist"
    original = plistlib.loads(info.read_bytes())
    modes = list(dict.fromkeys([*original.get("UIBackgroundModes", []), "audio"]))
    update_plist(info, {"CFBundleDisplayName": "SpokenLog",
                       "NSMicrophoneUsageDescription": microphone,
                       "UIBackgroundModes": modes})
    print("Apple app identity, microphone and background recording configured.")


def verify_macos_signature(app: Path) -> dict:
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)],
                   check=True)
    signed = plistlib.loads(subprocess.check_output(
        ["codesign", "-d", "--entitlements", ":-", str(app)],
        stderr=subprocess.PIPE))
    for key, value in MACOS_ENTITLEMENTS.items():
        if signed.get(key) is not value:
            raise ValueError(f"Incorrect signed entitlement: {key}")
    return signed


def verify_packages() -> None:
    version, build_number = app_version()
    ipa = ROOT / "dist/SpokenLog-iOS-unsigned.ipa"
    mac_zip = ROOT / "dist/SpokenLog-macOS.zip"
    expected = {"CFBundleIdentifier": BUNDLE_ID,
                "CFBundleShortVersionString": version,
                "CFBundleVersion": build_number}
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip():
            raise ValueError("Corrupt iOS archive")
        info = plistlib.loads(archive.read("Payload/Runner.app/Info.plist"))
        for key, value in expected.items():
            if str(info.get(key)) != value:
                raise ValueError(f"iOS {key} mismatch: {info.get(key)!r}")
        if not info.get("NSMicrophoneUsageDescription") or \
                "audio" not in info.get("UIBackgroundModes", []):
            raise ValueError("Missing recording permissions")
        if len(archive.read("Payload/Runner.app/Runner")) < 1024:
            raise ValueError("Missing compiled iOS executable")
    with zipfile.ZipFile(mac_zip) as archive:
        if archive.testzip():
            raise ValueError("Corrupt macOS archive")
        info = plistlib.loads(archive.read("SpokenLog.app/Contents/Info.plist"))
        for key, value in expected.items():
            if str(info.get(key)) != value:
                raise ValueError(f"macOS {key} mismatch: {info.get(key)!r}")
        if info.get("FLTEnableImpeller") is not False:
            raise ValueError("macOS renderer compatibility setting missing")
        binary = f"SpokenLog.app/Contents/MacOS/{info['CFBundleExecutable']}"
        if len(archive.read(binary)) < 1024:
            raise ValueError("Missing compiled macOS executable")
        helper = archive.getinfo("Uninstall-SpokenLog.command")
        if not ((helper.external_attr >> 16) & 0o111):
            raise ValueError("macOS uninstall helper is not executable")
        if archive.read(helper) != (ROOT / "tool/macos/Uninstall-SpokenLog.command").read_bytes():
            raise ValueError("macOS uninstall helper does not match source")
    # Inspect what users actually extract, not just the pre-packaging app.
    with tempfile.TemporaryDirectory(prefix="spokenlog-verify-") as directory:
        subprocess.run(["ditto", "-x", "-k", str(mac_zip), directory], check=True)
        entitlements = verify_macos_signature(Path(directory) / "SpokenLog.app")
    artifacts = []
    for path in (mac_zip, ipa):
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        artifacts.append({"file": path.name, "bytes": path.stat().st_size,
                          "sha256": digest})
    report = {
        "version": version, "build_number": build_number,
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"],
                                          cwd=ROOT, text=True).strip(),
        "flutter": subprocess.check_output(["flutter", "--version", "--machine"],
                                           cwd=ROOT, text=True).strip(),
        "ios_signing": "unsigned; re-sign before installation",
        "macos_signing": "ad-hoc; not notarized",
        "macos_entitlements": entitlements,
        "macos_renderer": "Skia (FLTEnableImpeller=false)",
        "physical_device_tests": False,
        "artifacts": artifacts,
    }
    (ROOT / "dist/BUILD-INFO.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-packages", action="store_true")
    args = parser.parse_args()
    verify_packages() if args.verify_packages else prepare()
