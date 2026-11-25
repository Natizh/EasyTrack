#!/usr/bin/env python3
"""Check the unsigned SideStore build before it can be distributed or installed."""

import pathlib
import plistlib
import re
import sys
import zipfile


APP = "EasyTrack.app"
ORIGINAL_ID = "local.easytrack.finance"
SOURCE_INFO = pathlib.Path(__file__).resolve().parent.parent / "EasyTrack/Info.plist"
FORBIDDEN_SUFFIXES = {
    ".sqlite", ".sqlite3", ".db", ".db3", ".sql", ".csv", ".xlsx", ".xls",
    ".wal", ".shm", ".bak", ".backup", ".p12", ".p8", ".pem", ".key",
    ".mobileprovision", ".pfx", ".cer", ".der", ".entitlements", ".xcent",
}
FORBIDDEN_NAMES = {"embedded.mobileprovision", "easytrack.json"}


def check_files(names, read):
    if any(".." in pathlib.PurePosixPath(name).parts for name in names):
        raise ValueError("IPA contains a path outside its app payload")
    info_name = f"Payload/{APP}/Info.plist"
    if info_name not in names:
        raise ValueError(f"IPA must contain {info_name}")
    if any(not name.startswith(f"Payload/{APP}/") and name != "Payload/" for name in names):
        raise ValueError("IPA contains files outside the EasyTrack app payload")
    if any(name.endswith("/") and name.startswith("Payload/") and not name.startswith(f"Payload/{APP}/") and name not in ("Payload/", f"Payload/{APP}/") for name in names):
        raise ValueError("IPA contains an unexpected app or directory")
    info = plistlib.loads(read(info_name))
    if info.get("CFBundleIdentifier") != ORIGINAL_ID:
        raise ValueError(f"original bundle identifier must be {ORIGINAL_ID}; found {info.get('CFBundleIdentifier')!r}. Rebuild with PRODUCT_BUNDLE_IDENTIFIER={ORIGINAL_ID}")
    if info.get("CFBundleExecutable") != "EasyTrack" or info.get("CFBundlePackageType") != "APPL":
        raise ValueError("unexpected app target or package type")
    platforms = info.get("CFBundleSupportedPlatforms", [])
    if platforms != ["iPhoneOS"] or info.get("DTPlatformName") != "iphoneos":
        raise ValueError("expected a Release build for a physical iOS device")
    if 1 not in info.get("UIDeviceFamily", []):
        raise ValueError("app target does not support iPhone")
    version, build = info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")
    if not isinstance(version, str) or not re.fullmatch(r"\d+(?:\.\d+){1,2}", version):
        raise ValueError("missing or invalid app version")
    if not isinstance(build, str) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("missing or invalid app build number")
    source = plistlib.loads(SOURCE_INFO.read_bytes())
    if (version, build) != (source.get("CFBundleShortVersionString"), source.get("CFBundleVersion")):
        raise ValueError("built app version or build number differs from repository source")
    executable = f"Payload/{APP}/EasyTrack"
    if executable not in names or read(executable)[:4] not in (b"\xca\xfe\xba\xbe", b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
        raise ValueError("missing or invalid EasyTrack executable")
    for name in names:
        relative = name.removeprefix(f"Payload/{APP}/")
        lower = relative.lower()
        if (pathlib.PurePosixPath(lower).suffix in FORBIDDEN_SUFFIXES
                or pathlib.PurePosixPath(lower).name in FORBIDDEN_NAMES
                or (lower.endswith(".json") and lower != "metadata.appintents/version.json")):
            raise ValueError(f"unexpected database, spreadsheet, backup, or provisioning file: {name}")
        if lower.startswith("_codesignature/") or "/_codesignature/" in lower:
            raise ValueError("app is signed; expected an unsigned IPA")
    print(f"Verified unsigned EasyTrack {version} ({build}), {ORIGINAL_ID}")


def main(path):
    if path.is_dir():
        names = {"Payload/", f"Payload/{APP}/"}
        names.update(f"Payload/{APP}/{item.relative_to(path).as_posix()}" for item in path.rglob("*") if item.is_file())
        check_files(names, lambda name: (path / name.removeprefix(f"Payload/{APP}/")).read_bytes())
    else:
        with zipfile.ZipFile(path) as archive:
            names = set(archive.namelist())
            if len(names) != len(archive.namelist()):
                raise ValueError("IPA contains duplicate paths")
            corrupt = archive.testzip()
            if corrupt is not None:
                raise ValueError(f"IPA has a damaged member: {corrupt}")
            check_files(names, archive.read)


if __name__ == "__main__":
    try:
        main(pathlib.Path(sys.argv[1]))
    except (IndexError, OSError, ValueError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"IPA validation failed: {error}", file=sys.stderr)
        sys.exit(1)
