#!/usr/bin/env python3
"""Test Home, localization and notification flows with fictional data in a separate simulator app."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = "local.easytrack.finance.accountingaudit"


def run(arguments, *, env=None, log=None):
    if log is None:
        subprocess.run(arguments, cwd=ROOT, env=env, check=True)
    else:
        with log.open("w", encoding="utf-8") as output:
            result = subprocess.run(arguments, cwd=ROOT, env=env, stdout=output,
                                    stderr=subprocess.STDOUT)
        if result.returncode:
            print("\n".join(log.read_text().splitlines()[-35:]))
            raise RuntimeError(f"{arguments[0]} failed; full output: {log}")


def device_state(uuid):
    result = subprocess.run(["xcrun", "simctl", "list", "devices", "--json"],
                            capture_output=True, text=True, check=True)
    devices = json.loads(result.stdout)["devices"]
    for group in devices.values():
        for device in group:
            if device["udid"] == uuid and device.get("isAvailable") and device["name"] == "iPhone 17 Pro":
                return device["state"]
    raise RuntimeError("Use the existing available iPhone 17 Pro simulator UUID")


def app_container(uuid):
    result = subprocess.run(["xcrun", "simctl", "get_app_container", uuid, BUNDLE, "data"],
                            capture_output=True, text=True)
    if result.returncode == 0:
        return Path(result.stdout.strip())
    if "No such file or directory" in result.stderr:
        return None
    raise RuntimeError(f"Could not verify isolated app installation: {result.stderr.strip()}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Existing iPhone 17 Pro simulator UUID")
    parser.add_argument("--derived-data", type=Path, default=ROOT / "DerivedData")
    parser.add_argument("--swift-build", type=Path, default=ROOT / ".build")
    parser.add_argument("--only-test", action="append", help="Run one named UI test; may be repeated")
    args = parser.parse_args()
    original_state = device_state(args.device)
    free = shutil.disk_usage(ROOT).free / (1024 ** 3)
    print(f"Before test: {free:.1f} GiB free", flush=True)
    if original_state != "Booted":
        run(["xcrun", "simctl", "boot", args.device])
        run(["xcrun", "simctl", "bootstatus", args.device, "-b"])
    installed_by_run = False
    try:
        if app_container(args.device) is not None:
            raise RuntimeError("The isolated test app already exists; its data will not be changed")
        with tempfile.TemporaryDirectory(prefix="AccountingAudit-", suffix=".xcodeproj", dir=ROOT) as project_name, \
             tempfile.TemporaryDirectory(prefix="AccountingFixture-") as fixture_name:
            project = Path(project_name)
            fixture_dir = Path(fixture_name)
            shutil.copytree(ROOT / "EasyTrack.xcodeproj", project, dirs_exist_ok=True)
            pbx = project / "project.pbxproj"
            original = "PRODUCT_BUNDLE_IDENTIFIER = local.easytrack.finance;"
            contents = pbx.read_text()
            if contents.count(original) != 2:
                raise RuntimeError("Unexpected app bundle settings; refusing the test build")
            pbx.write_text(contents.replace(original, f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};"))
            scheme = project / "xcshareddata/xcschemes/EasyTrack.xcscheme"
            scheme.write_text(scheme.read_text().replace("container:EasyTrack.xcodeproj",
                                                         f"container:{project.name}"))
            common = ["xcodebuild", "-project", str(project), "-scheme", "EasyTrack",
                      "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={args.device}",
                      "-derivedDataPath", str(args.derived_data.resolve()),
                      "-parallel-testing-enabled", "NO", "-jobs", "2", "CODE_SIGNING_ALLOWED=NO",
                      "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG EASYTRACK_ACCOUNTING_AUDIT EASYTRACK_REVIEW35"]
            run(common + ["build-for-testing"], log=fixture_dir / "build.log")
            print(f"After build: {shutil.disk_usage(ROOT).free / (1024 ** 3):.1f} GiB free", flush=True)
            fixture = fixture_dir / "ledger.sqlite"
            environment = dict(os.environ, EASYTRACK_SHOWCASE_DB_OUTPUT=str(fixture))
            run(["swift", "test", "--jobs", "2", "--scratch-path", str(args.swift_build.resolve()),
                 "--filter", "ShowcaseFixtureTests"], env=environment, log=fixture_dir / "fixture.log")
            app = args.derived_data.resolve() / "Build/Products/Debug-iphonesimulator/EasyTrack.app"
            with (app / "Info.plist").open("rb") as file:
                if plistlib.load(file)["CFBundleIdentifier"] != BUNDLE:
                    raise RuntimeError("Built app identifier is not isolated")
            run(["xcrun", "simctl", "install", args.device, str(app)])
            installed_by_run = True
            container = app_container(args.device)
            if container is None:
                raise RuntimeError("Isolated test app did not install")
            support = container / "Library/Application Support"
            support.mkdir(parents=True, exist_ok=True)
            target = support / "EasyTrack.sqlite"
            if target.exists():
                raise RuntimeError("The isolated app already has a ledger; refusing overwrite")
            shutil.copy2(fixture, target)
            tests = args.only_test or [
                "testHomeIncomeAndExpensesOpenCompletePeriodActivity",
                "testItalianDefaultAndEnglishSwitchPreservesSyntheticLedger",
                "testOverReimbursementShowsAdditionalEarningsWithoutExtraMovement",
                "testReview35FirstCapturePromptAndDeletionPersist",
                "testReview35CrossAccountSettlementPickerAndCancel",
            ]
            run(common + [f"-only-testing:EasyTrackUITests/EasyTrackUITests/{name}" for name in tests]
                + ["test-without-building"], log=fixture_dir / "ui.log")
            print(f"{len(tests)} isolated synthetic UI test(s) passed: {', '.join(tests)}", flush=True)
    finally:
        if device_state(args.device) != "Booted":
            run(["xcrun", "simctl", "boot", args.device])
            run(["xcrun", "simctl", "bootstatus", args.device, "-b"])
        if installed_by_run and app_container(args.device) is not None:
            run(["xcrun", "simctl", "uninstall", args.device, BUNDLE])
        if original_state != "Booted":
            run(["xcrun", "simctl", "shutdown", args.device])
        print(f"After test: {shutil.disk_usage(ROOT).free / (1024 ** 3):.1f} GiB free", flush=True)


if __name__ == "__main__":
    main()
