#!/usr/bin/env python3
"""Capture six real EasyTrack screens on an existing iPhone simulator.

This creates a temporary project with a separate bundle ID, installs only that
app, uses a synthetic SQLite fixture, and removes the app after export.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "local.easytrack.finance.showcase"
ASSETS = ROOT / "docs/assets/showcase"
SCREENS = ("home", "activity", "analytics", "quick-entry", "automation", "accounts")
DERIVED = ROOT / ".build/XcodeDerivedData"


def command(args: list[str], *, env: dict[str, str] | None = None,
            log: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    if log:
        with log.open("w", encoding="utf-8") as output:
            result = subprocess.run(args, cwd=ROOT, env=env, text=True, stdout=output,
                                    stderr=subprocess.STDOUT, check=False)
        if result.returncode and check:
            lines = log.read_text(encoding="utf-8").splitlines()
            relevant = [line for line in lines if "error:" in line or "TEST FAILED" in line
                        or "BUILD FAILED" in line or "Test Case" in line]
            print("\n".join((relevant or lines[-15:])[-20:]), file=sys.stderr)
            raise RuntimeError(f"{args[0]} exited with status {result.returncode}")
        return result
    result = subprocess.run(args, cwd=ROOT, env=env, text=True, capture_output=True, check=False)
    if result.returncode and check:
        raise RuntimeError(f"{' '.join(args[:3])}: {result.stderr.strip() or result.stdout.strip()}")
    return result


def available_device(uuid: str) -> dict[str, object]:
    devices = json.loads(command(["xcrun", "simctl", "list", "devices", "--json"]).stdout)["devices"]
    for group in devices.values():
        for device in group:
            if device["udid"] == uuid:
                if not device.get("isAvailable") or "iPhone" not in device["deviceTypeIdentifier"]:
                    raise RuntimeError("The selected UUID is not an available iPhone simulator")
                return device
    raise RuntimeError("No installed iPhone simulator has that UUID; no device was created")


def clone_project(destination: Path) -> None:
    shutil.copytree(ROOT / "EasyTrack.xcodeproj", destination, dirs_exist_ok=True)
    project = destination / "project.pbxproj"
    text = project.read_text()
    old = "PRODUCT_BUNDLE_IDENTIFIER = local.easytrack.finance;"
    if text.count(old) != 2:
        raise RuntimeError("The app bundle setting changed; refusing to modify the source project")
    project.write_text(text.replace(old, f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};"))
    scheme = destination / "xcshareddata/xcschemes/EasyTrack.xcscheme"
    text = scheme.read_text()
    text = text.replace("container:EasyTrack.xcodeproj", f"container:{destination.name}")
    scheme.write_text(text)


def report_space(label: str) -> None:
    free_gib = shutil.disk_usage(ROOT).free / (1024 ** 3)
    print(f"{label}: {free_gib:.1f} GiB available", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="UUID of an already installed iPhone simulator")
    parser.add_argument("--replace", action="store_true", help="Replace only the generated showcase images")
    args = parser.parse_args()
    if not shutil.which("magick"):
        parser.error("ImageMagick 7 is required only to compose the README images")
    expected = [ASSETS / f"phone-{name}.png" for name in SCREENS]
    expected += [ASSETS / "hero.png", ASSETS / "social-preview.png"]
    if not args.replace and any(path.exists() for path in expected):
        parser.error("Showcase images already exist; use --replace to regenerate them")

    device = available_device(args.device)
    originally_booted = device["state"] == "Booted"
    appearance = ""
    installed = False
    status_overridden = False
    report_space("Before capture")
    try:
        if not originally_booted:
            command(["xcrun", "simctl", "boot", args.device])
            command(["xcrun", "simctl", "bootstatus", args.device, "-b"])
        existing = command(["xcrun", "simctl", "get_app_container", args.device, BUNDLE_ID, "data"],
                           check=False)
        if existing.returncode == 0:
            raise RuntimeError("The isolated showcase app already exists; refusing to touch its data")
        if "No such file or directory" not in existing.stderr:
            raise RuntimeError(f"Could not verify the isolated app is absent: {existing.stderr.strip()}")
        appearance = command(["xcrun", "simctl", "ui", args.device, "appearance"],
                             check=False).stdout.strip().lower()
        command(["xcrun", "simctl", "ui", args.device, "appearance", "light"])
        command(["xcrun", "simctl", "status_bar", args.device, "override", "--time", "9:41",
                 "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged",
                 "--batteryLevel", "100"])
        status_overridden = True
        with tempfile.TemporaryDirectory(prefix="EasyTrackShowcase-", suffix=".xcodeproj", dir=ROOT) as project_name, \
             tempfile.TemporaryDirectory(prefix="capture-", dir=ROOT / ".build") as scratch_name:
            project = Path(project_name)
            scratch = Path(scratch_name)
            clone_project(project)
            destination = f"platform=iOS Simulator,id={args.device}"
            common = ["xcodebuild", "-project", str(project), "-scheme", "EasyTrack",
                      "-configuration", "Debug", "-destination", destination,
                      "-derivedDataPath", str(DERIVED), "-parallel-testing-enabled", "NO",
                      "CODE_SIGNING_ALLOWED=NO",
                      "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG EASYTRACK_SHOWCASE_CAPTURE",
                      "-jobs", "2"]
            print("Building isolated EasyTrack and UI test runner…", flush=True)
            command(common + ["build-for-testing"], log=scratch / "build.log")
            report_space("After build")

            fixture = scratch / "ledger.sqlite"
            env = dict(os.environ, EASYTRACK_SHOWCASE_DB_OUTPUT=str(fixture))
            print("Generating and checking fictional ledger…", flush=True)
            command(["swift", "test", "--jobs", "2", "--filter", "ShowcaseFixtureTests"],
                    env=env, log=scratch / "fixture.log")
            if not fixture.is_file():
                raise RuntimeError("Synthetic fixture test did not produce its ledger")

            app = DERIVED / "Build/Products/Debug-iphonesimulator/EasyTrack.app"
            with (app / "Info.plist").open("rb") as plist:
                actual_bundle = plistlib.load(plist)["CFBundleIdentifier"]
            if actual_bundle != BUNDLE_ID:
                raise RuntimeError("Built bundle ID is not isolated; refusing simulator installation")
            command(["xcrun", "simctl", "install", args.device, str(app)])
            installed = True
            container = Path(command(["xcrun", "simctl", "get_app_container", args.device,
                                      BUNDLE_ID, "data"]).stdout.strip())
            support = container / "Library/Application Support"
            support.mkdir(parents=True, exist_ok=True)
            target = support / "EasyTrack.sqlite"
            if target.exists():
                raise RuntimeError("Isolated app already has a ledger; refusing to overwrite it")
            shutil.copy2(fixture, target)

            result = scratch / "capture.xcresult"
            print("Capturing real app screens…", flush=True)
            command(common + ["-resultBundlePath", str(result),
                      "-only-testing:EasyTrackUITests/EasyTrackUITests/testCaptureShowcaseHomeActivityAndEntry",
                      "-only-testing:EasyTrackUITests/EasyTrackUITests/testCaptureShowcaseAnalytics",
                      "-only-testing:EasyTrackUITests/EasyTrackUITests/testCaptureShowcaseAccounts",
                      "-only-testing:EasyTrackUITests/EasyTrackUITests/testCaptureShowcaseAutomation",
                      "test-without-building"], log=scratch / "capture.log")
            exported = scratch / "attachments"
            command(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                     "--output-path", str(exported)])
            manifest = json.loads((exported / "manifest.json").read_text())
            found: dict[str, Path] = {}
            for test in manifest:
                for attachment in test["attachments"]:
                    name = Path(attachment["suggestedHumanReadableName"]).stem.split("_", 1)[0].lower()
                    if name in SCREENS:
                        found[name] = exported / attachment["exportedFileName"]
            missing = set(SCREENS) - set(found)
            if missing:
                names = [attachment["suggestedHumanReadableName"] for test in manifest
                         for attachment in test["attachments"]]
                summary = [line for line in (scratch / "capture.log").read_text().splitlines()
                           if "Test Case" in line or "skipped" in line or "TEST " in line]
                raise RuntimeError(f"Missing UI test attachments: {', '.join(sorted(missing))}; "
                                   f"observed {names}; test result {summary[-8:]}")
            screens = scratch / "screens"
            screens.mkdir()
            for name, path in found.items():
                shutil.copy2(path, screens / f"{name}.png")
            rendered = scratch / "rendered"
            command([sys.executable, str(ROOT / "scripts/render_showcase.py"),
                     "--screens", str(screens), "--output", str(rendered)])
            ASSETS.mkdir(parents=True, exist_ok=True)
            for path in expected:
                os.replace(rendered / path.name, path)
            report_space("After capture")
    finally:
        if installed:
            command(["xcrun", "simctl", "terminate", args.device, BUNDLE_ID], check=False)
            for _ in range(3):
                removed = command(["xcrun", "simctl", "uninstall", args.device, BUNDLE_ID],
                                  check=False)
                time.sleep(4)
                first = command(["xcrun", "simctl", "get_app_container", args.device,
                                 BUNDLE_ID, "data"], check=False)
                time.sleep(2)
                second = command(["xcrun", "simctl", "get_app_container", args.device,
                                  BUNDLE_ID, "data"], check=False)
                if first.returncode != 0 and second.returncode != 0:
                    break
            else:
                print(f"Warning: isolated app still installed: {removed.stderr.strip()}",
                      file=sys.stderr)
        if status_overridden:
            command(["xcrun", "simctl", "status_bar", args.device, "clear"], check=False)
        if appearance in {"light", "dark"}:
            command(["xcrun", "simctl", "ui", args.device, "appearance", appearance], check=False)
        if not originally_booted:
            command(["xcrun", "simctl", "shutdown", args.device], check=False)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"showcase capture failed: {error}", file=sys.stderr)
        raise SystemExit(1)
