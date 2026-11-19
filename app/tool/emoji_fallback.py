#!/usr/bin/env python3
"""Mirrors the web engine's Noto Color Emoji subsets into web/fonts/fallback/.

The web builds load nothing from Google: `web/flutter_bootstrap.js`
points the engine's font fallback at `fonts/fallback/` next to the app instead of
`fonts.gstatic.com`. The engine asks for emoji there under the exact paths of its own
list -- `notocoloremoji/v32/<hash>.<n>.woff2`, twelve subsets, each loaded only once a
page shows one of its emoji. That list belongs to the Flutter version: a newer engine
may ask for other files, find none, and show emoji as boxes without a word.

This script reads the list from the Flutter SDK on PATH (or `FLUTTER_ROOT`), downloads
the missing subsets once and removes those the engine no longer names. `--check` only
compares and fails on a difference -- CI runs it, so a Flutter update that moves the
files cannot slip through.

Only the emoji are mirrored. Other scripts (CJK, Arabic, ...) still show as boxes;
their subsets would add tens of megabytes for text a family wiki rarely holds.

Usage:  python3 tool/emoji_fallback.py           # refresh web/fonts/fallback/
        python3 tool/emoji_fallback.py --check   # fail if it is out of date
"""
import os
import pathlib
import re
import shutil
import sys
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
TARGET = HERE.parent / "web" / "fonts" / "fallback"
FAMILY_DIR = "notocoloremoji"
SOURCE_URL = "https://fonts.gstatic.com/s/"

# Where the generated list lies inside the SDK: the engine sources in the checkout,
# or the web SDK copy once `flutter precache --web` or a web build fetched it.
DATA_FILES = [
    "engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart",
    "bin/cache/flutter_web_sdk/lib/_engine/engine/font_fallback_data.dart",
]

ENTRY = re.compile(r"'Noto Color Emoji \d+',\s*'(" + FAMILY_DIR + r"/[^']+\.woff2)'")


def flutter_root() -> pathlib.Path:
    if root := os.environ.get("FLUTTER_ROOT"):
        return pathlib.Path(root)
    flutter = shutil.which("flutter")
    if flutter is None:
        sys.exit("flutter is not on PATH, and FLUTTER_ROOT is not set.")
    return pathlib.Path(flutter).resolve().parent.parent


def wanted_paths() -> list[str]:
    root = flutter_root()
    for relative in DATA_FILES:
        data = root / relative
        if data.is_file():
            paths = ENTRY.findall(data.read_text(encoding="utf-8"))
            if not paths:
                sys.exit(f"No Noto Color Emoji entries in {data} -- has its format changed?")
            return paths
    sys.exit(f"No font_fallback_data.dart under {root}.")


def present_paths() -> set[str]:
    family = TARGET / FAMILY_DIR
    if not family.is_dir():
        return set()
    return {p.relative_to(TARGET).as_posix() for p in family.rglob("*") if p.is_file()}


def main() -> None:
    check = sys.argv[1:] == ["--check"]
    wanted = wanted_paths()
    present = present_paths()
    missing = [p for p in wanted if p not in present]
    stale = sorted(present - set(wanted))

    if check:
        if missing or stale:
            for p in missing:
                print(f"missing: web/fonts/fallback/{p}")
            for p in stale:
                print(f"stale:   web/fonts/fallback/{p}")
            sys.exit(
                "The emoji fallback fonts do not match this Flutter version's engine. "
                "Run `python3 tool/emoji_fallback.py` in app/ and commit the result."
            )
        print(f"Emoji fallback fonts match the engine ({len(wanted)} files).")
        return

    for p in missing:
        file = TARGET / p
        file.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(SOURCE_URL + p) as response:
            body = response.read()
        if not body.startswith(b"wOF2"):
            sys.exit(f"{SOURCE_URL + p} is not a WOFF2 file.")
        file.write_bytes(body)
        print(f"fetched: {p} ({len(body) // 1024} KB)")
    for p in stale:
        (TARGET / p).unlink()
        print(f"removed: {p}")
    for directory in sorted((TARGET / FAMILY_DIR).rglob("*"), reverse=True):
        if directory.is_dir() and not any(directory.iterdir()):
            directory.rmdir()
    if not missing and not stale:
        print("Already up to date.")


if __name__ == "__main__":
    main()
