#!/usr/bin/env python3
"""Lays the store pictures out where fastlane looks for them.

The pictures are drawn by app/test/store (STORE_OUT=<dir> flutter test test/store);
they are build output and not kept in the repository. fastlane wants them elsewhere,
and each store in its own layout:

- App Store (deliver): app/ios/fastlane/screenshots/<locale>/, one folder per
  language; it tells the iPhone from the iPad by the pictures' size, and orders
  them by name.
- Google Play (supply): app/android/fastlane/metadata/android/<locale>/images/, the
  phone's and the tablet's in folders of their own, beside the feature graphic and
  the 512-pixel icon.

    tool/store_pictures.py build/store
"""

import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"
LOCALES = {"de": "de-DE", "en": "en-US"}

# The test's device folders, and where each store wants them.
IOS_DEVICES = ["iphone", "ipad"]
ANDROID_DEVICES = {
    "androidPhone": "phoneScreenshots",
    "androidTablet": "tenInchScreenshots",
}
ICON = APP / "assets/app_icon/google_play_icon_512.png"


def pictures(folder: pathlib.Path) -> list:
    found = sorted(folder.glob("*.png"))
    if not found:
        sys.exit(f"No pictures in {folder}: run the store test with STORE_OUT first")
    return found


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    drawn = pathlib.Path(sys.argv[1]).resolve()

    ios = APP / "ios/fastlane/screenshots"
    shutil.rmtree(ios, ignore_errors=True)
    for language, locale in LOCALES.items():
        target = ios / locale
        target.mkdir(parents=True)
        for device in IOS_DEVICES:
            for picture in pictures(drawn / language / device):
                # "01-start-board.png" from the iPhone becomes
                # "01-iphone-start-board.png": the number first keeps the order.
                number, scene = picture.name.split("-", 1)
                shutil.copy(picture, target / f"{number}-{device}-{scene}")

        images = APP / "android/fastlane/metadata/android" / locale / "images"
        shutil.rmtree(images, ignore_errors=True)
        for device, folder in ANDROID_DEVICES.items():
            target = images / folder
            target.mkdir(parents=True)
            for picture in pictures(drawn / language / device):
                shutil.copy(picture, target / picture.name)
        shutil.copy(drawn / language / "feature-graphic.png", images / "featureGraphic.png")
        shutil.copy(ICON, images / "icon.png")

    print(f"Store pictures laid out from {drawn}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
