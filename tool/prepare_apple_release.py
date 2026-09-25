"""Configure generated Apple runners, or verify their release archives.

Called by codemagic.yaml after flutter create. No signing credentials are used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "io.github.blueb.spokenlog"


def app_version() -> tuple[str, str]:
    match = re.search(r"^version:\s*([\d.]+)\+(\d+)\s*$",
                      (ROOT / "pubspec.yaml").read_text(), re.MULTILINE)
    if match is None or match[1] != "0.1.0":
        raise ValueError("This workflow only replaces the v0.1.0 release.")
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
    update_plist(ROOT / "macos/Runner/Info.plist",
                 {"NSMicrophoneUsageDescription": microphone})
    for name in ("DebugProfile.entitlements", "Release.entitlements"):
        update_plist(ROOT / "macos/Runner" / name, {
            "com.apple.security.device.audio-input": True,
            "com.apple.security.network.client": True,
            "com.apple.security.files.user-selected.read-write": True,
        })
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
        binary = f"SpokenLog.app/Contents/MacOS/{info['CFBundleExecutable']}"
        if len(archive.read(binary)) < 1024:
            raise ValueError("Missing compiled macOS executable")
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
