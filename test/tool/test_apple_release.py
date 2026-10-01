"""Release-signing regressions; stdlib only, no Apple host required."""
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tool import prepare_apple_release as release


class AppleReleaseTest(unittest.TestCase):
    def test_version_follows_source_instead_of_old_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(release, "ROOT", root):
                for value, expected in [("0.1.0+9", ("0.1.0", "9")),
                                        ("0.1.2+10", ("0.1.2", "10"))]:
                    (root / "pubspec.yaml").write_text(f"version: {value}\n")
                    self.assertEqual(release.app_version(), expected)
                (root / "pubspec.yaml").write_text("version: 0.1+10\n")
                with self.assertRaises(ValueError):
                    release.app_version()

    def test_prepare_keeps_existing_storage_locations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                "pubspec.yaml": "version: 0.1.0+7\n",
                "macos/Runner/Configs/AppInfo.xcconfig":
                    "PRODUCT_NAME = spokenlog\nPRODUCT_BUNDLE_IDENTIFIER = old\n",
                "ios/Runner.xcodeproj/project.pbxproj":
                    f"PRODUCT_BUNDLE_IDENTIFIER = {release.BUNDLE_ID};\n",
            }
            for name, text in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            for name in ("macos/Runner/Info.plist", "ios/Runner/Info.plist",
                         "macos/Runner/Release.entitlements",
                         "macos/Runner/DebugProfile.entitlements"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))
            with patch.object(release, "ROOT", root):
                release.prepare()
            mac_info = plistlib.loads((root / "macos/Runner/Info.plist").read_bytes())
            ios_info = plistlib.loads((root / "ios/Runner/Info.plist").read_bytes())
            self.assertIs(mac_info["FLTEnableImpeller"], False)
            self.assertNotIn("FLTEnableImpeller", ios_info)
            for name in ("Release.entitlements", "DebugProfile.entitlements"):
                actual = plistlib.loads((root / "macos/Runner" / name).read_bytes())
                self.assertEqual(actual, release.MACOS_ENTITLEMENTS)
                self.assertIs(actual["com.apple.security.app-sandbox"], False)

    def test_final_signature_requires_permissions_and_existing_storage_mode(self):
        app = Path("extracted/SpokenLog.app")
        with patch.object(release.subprocess, "run") as verify, \
                patch.object(release.subprocess, "check_output") as inspect:
            inspect.return_value = plistlib.dumps(release.MACOS_ENTITLEMENTS)
            self.assertEqual(release.verify_macos_signature(app), release.MACOS_ENTITLEMENTS)
            verify.assert_called_with(
                ["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
            inspect.return_value = b""
            with self.assertRaises(ValueError):
                release.verify_macos_signature(app)
            for key in release.MACOS_ENTITLEMENTS:
                with self.subTest(key=key):
                    invalid = dict(release.MACOS_ENTITLEMENTS)
                    invalid[key] = not invalid[key]
                    inspect.return_value = plistlib.dumps(invalid)
                    with self.assertRaisesRegex(ValueError, "Incorrect signed entitlement"):
                        release.verify_macos_signature(app)


if __name__ == "__main__":
    unittest.main()
