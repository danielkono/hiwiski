#!/usr/bin/env python3
"""Checks the store texts that fastlane uploads against the stores' limits.

App Store Connect and the Play Console refuse a text that is a character too long,
and they only say so during the upload, long after the change was merged. Both stores
count characters, not bytes. The long description is written once and used by both
stores, and so are the release notes; this also keeps the copies from drifting
apart.

    tool/store_metadata.py
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
IOS = ROOT / "app/ios/fastlane/metadata"
ANDROID = ROOT / "app/android/fastlane/metadata/android"
LOCALES = ["de-DE", "en-US"]

# File -> the most characters the store takes; None for a file that must only exist.
IOS_LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "promotional_text.txt": 170,
    "keywords.txt": 100,
    "description.txt": 4000,
    "release_notes.txt": 4000,
    "support_url.txt": None,
    "marketing_url.txt": None,
    "privacy_url.txt": None,
}
ANDROID_LIMITS = {
    "title.txt": 30,
    "short_description.txt": 80,
    "full_description.txt": 4000,
    # The release notes of every build (the internal lane uploads them with it).
    "changelogs/default.txt": 500,
}


def text(path: pathlib.Path) -> str:
    # fastlane strips the final line break, so it does not count.
    return path.read_text(encoding="utf-8").rstrip("\n")


def check(folder: pathlib.Path, limits: dict, problems: list) -> None:
    for name, limit in limits.items():
        path = folder / name
        if not path.is_file():
            problems.append(f"{path.relative_to(ROOT)} is missing")
            continue
        length = len(text(path))
        if length == 0:
            problems.append(f"{path.relative_to(ROOT)} is empty")
        elif limit is not None and length > limit:
            problems.append(
                f"{path.relative_to(ROOT)} has {length} characters, the store takes {limit}"
            )


def main() -> int:
    problems: list = []
    for locale in LOCALES:
        check(IOS / locale, IOS_LIMITS, problems)
        check(ANDROID / locale, ANDROID_LIMITS, problems)
        for ios_name, android_name in [
            ("description.txt", "full_description.txt"),
            ("release_notes.txt", "changelogs/default.txt"),
        ]:
            ios = IOS / locale / ios_name
            android = ANDROID / locale / android_name
            if ios.is_file() and android.is_file() and text(ios) != text(android):
                problems.append(
                    f"{android.relative_to(ROOT)} differs from {ios.relative_to(ROOT)}"
                )
        keywords = IOS / locale / "keywords.txt"
        if keywords.is_file() and ", " in text(keywords):
            # A space after a comma takes a character from the 100 and adds nothing.
            problems.append(f"{keywords.relative_to(ROOT)}: no space after a comma")
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
