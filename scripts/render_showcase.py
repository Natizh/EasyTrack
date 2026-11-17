#!/usr/bin/env python3
"""Frame real simulator captures for the README; requires ImageMagick 7."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path


SCREENS = ("home", "activity", "analytics", "quick-entry", "automation", "accounts")
FONT = Path("/System/Library/Fonts/SFNS.ttf")
BOLD_FONT = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")


def run(*args: object) -> None:
    subprocess.run([str(part) for part in args], check=True)


def frame_screen(source: Path, output: Path, scratch: Path) -> None:
    resized = scratch / "resized.png"
    mask = scratch / "mask.png"
    rounded = scratch / "rounded.png"
    frame = scratch / "frame.png"
    run("magick", source, "-resize", "460x990^", "-gravity", "center",
        "-extent", "460x990", "-strip", resized)
    run("magick", "-size", "460x990", "xc:none", "-fill", "white",
        "-draw", "roundrectangle 0,0 459,989 56,56", mask)
    run("magick", resized, mask, "-alpha", "off", "-compose", "CopyOpacity",
        "-composite", rounded)
    run("magick", "-size", "480x1010", "xc:none", "-fill", "#152225",
        "-stroke", "#344549", "-strokewidth", "2",
        "-draw", "roundrectangle 1,1 478,1008 68,68", frame)
    run("magick", frame, rounded, "-geometry", "+10+10", "-compose", "Over",
        "-composite", "-strip", "-define", "png:compression-level=9", output)


def hero(phones: Path, output: Path) -> None:
    run("magick", "-size", "1600x1020", "xc:#F5F7F5",
        "-fill", "#E8F0ED", "-draw", "ellipse 800,510 620,410 0,360",
        "(", phones / "phone-activity.png", "-resize", "345x726", ")",
        "-geometry", "+130+190", "-composite",
        "(", phones / "phone-automation.png", "-resize", "345x726", ")",
        "-geometry", "+1125+190", "-composite",
        "(", phones / "phone-home.png", "-resize", "470x989", ")",
        "-geometry", "+565+15", "-composite", "-strip",
        "-define", "png:compression-level=9", output)


def social(phones: Path, output: Path) -> None:
    run("magick", "-size", "1280x640", "xc:#F5F7F5",
        "-fill", "#DCECE7", "-draw", "ellipse 1010,355 400,300 0,360",
        "-stroke", "#23766F", "-strokewidth", "5",
        "-draw", "line 82,156 160,156", "-stroke", "none",
        "-font", BOLD_FONT, "-fill", "#17383B", "-pointsize", "84",
        "-gravity", "NorthWest", "-annotate", "+82+184", "EasyTrack",
        "-font", FONT, "-fill", "#4D6262", "-pointsize", "31",
        "-annotate", "+87+308", "Private finance, made simple.",
        "-pointsize", "23", "-annotate", "+87+500", "SwiftUI  ·  SQLite  ·  On-device by design",
        "(", phones / "phone-activity.png", "-resize", "245x516", ")",
        "-geometry", "+991+78", "-composite",
        "(", phones / "phone-home.png", "-resize", "296x623", ")",
        "-geometry", "+700+8", "-composite", "-strip",
        "-define", "png:compression-level=9", output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screens", type=Path, required=True,
                        help="Folder with six real simulator PNG captures")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--replace", action="store_true", help="Replace only the generated showcase PNGs")
    args = parser.parse_args()
    if not shutil.which("magick"):
        parser.error("ImageMagick 7 (`magick`) is required for presentation assets only")
    if not FONT.exists() or not BOLD_FONT.exists():
        parser.error("macOS system fonts were not found")
    expected = [args.output / f"phone-{name}.png" for name in SCREENS]
    expected += [args.output / "hero.png", args.output / "social-preview.png"]
    if not args.replace and any(path.exists() for path in expected):
        parser.error("Showcase assets already exist; pass --replace to regenerate them")
    for name in SCREENS:
        source = args.screens / f"{name}.png"
        if not source.is_file():
            parser.error(f"Missing real simulator capture: {source}")
        dimensions = subprocess.check_output(["magick", "identify", "-format", "%w %h", str(source)], text=True)
        width, height = map(int, dimensions.split())
        if width < 900 or height < 1800:
            parser.error(f"Unexpected simulator capture dimensions: {source} ({dimensions})")
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="easytrack-frames-") as temporary:
        scratch = Path(temporary)
        for name in SCREENS:
            frame_screen(args.screens / f"{name}.png", args.output / f"phone-{name}.png", scratch)
        hero(args.output, args.output / "hero.png")
        social(args.output, args.output / "social-preview.png")
    for path in expected:
        print(f"{path}: {path.stat().st_size // 1024} KiB")


if __name__ == "__main__":
    main()
