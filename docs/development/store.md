# The store listing

What the App Store and Google Play show about the app — texts and pictures — lives
in this repository and is checked like the code.

## Texts

| Store | Folder |
| --- | --- |
| App Store | `app/ios/fastlane/metadata/{de-DE,en-US}/` — name, subtitle, promotional text, description, keywords, URLs |
| Google Play | `app/android/fastlane/metadata/android/{de-DE,en-US}/` — title, short and full description |

The release notes are the same text for every version: the app keeps growing, and
what changed is on the website's "What's new" (`release_notes.txt`, and Play's
`changelogs/default.txt`, which goes up with every build).

`tool/store_metadata.py` checks them against the stores' limits (Play's release
notes: 500 characters), and that Play's description and release notes are the App
Store's. CI runs it.

## Pictures

Six pictures per device, light only, German and English, and Play's feature graphic:

| Device | Picture | Screen inside |
| --- | --- | --- |
| iPhone 6.9″ | 1320 × 2868 | 1320 × 2868 |
| iPad 13″ | 2064 × 2752 | 2064 × 2752 |
| Android phone | 1080 × 1920 | 1080 × 2400 |
| Android tablet | 1600 × 2560 | 1600 × 2560 |
| Play feature graphic | 1024 × 500 | — |

They are drawn by a test, `app/test/store/`, from the demo's sample data:

1. **The screen.** The scenes the website shows too (`test/scenes/scene_shots.dart`),
   with the app's navigation, at each device's size, pixel density and safe area, on
   a fixed day (Wednesday, 13 May 2026, 9:41) — the app reads the time only through
   `package:clock` for that (`clock_now`).
2. **The picture.** `store_shot.dart` puts the screen into the design: a label, a
   headline and a line below it (`store_texts.dart`), the device frame with its status
   bar. Every measure is a share of the picture's width, so one design covers every
   size.

**The pictures are golden files**, at a quarter of their size in
`app/test/store/goldens/`. A change to the app that shows in a store picture fails
the test: the pictures in the stores are due for an update.

Fonts render a little differently on every system. The goldens are therefore drawn
and compared only on Linux on x86-64, as CI runs them; on a Mac `flutter test` skips
them. There, `tool/store_shots.sh` runs them in a container with the Flutter version
from `app/.fvmrc`:

```sh
tool/store_shots.sh            # compare; differences land in app/test/store/failures/
tool/store_shots.sh --update   # draw the goldens anew, then look at them in the diff
```

When CI fails on them, the artifact `store-picture-differences` holds what it drew
and the difference.

The pictures at full size, for the stores and for looking at them, come from the same
test:

```sh
cd app && STORE_OUT=build/store flutter test test/store
```

`build/store/<lang>/<device>/<nn>-<scene>.png`, the raw screens under `raw/`. On a Mac
they look as good, only not pixel for pixel like the goldens.

## Upload

A release tag uploads the listing (`release.yml`, the jobs `store-*`):

| | When | What |
| --- | --- | --- |
| `store-pictures` | every tag | draws the pictures, if the goldens, the store texts or the icon changed since the last release tag |
| `store-play` | when they changed | `fastlane metadata` in `app/android`: texts, screenshots, feature graphic, icon |
| `store-apple` | every tag | `fastlane metadata` in `app/ios`: texts and release notes of the new version, the screenshots when they changed |

Apple keeps texts and pictures per version: the lane edits the version being
released, and makes it if App Store Connect has none to edit; a new version takes the
previous one's screenshots over. Nothing is submitted for review, on either store.

By hand, with the keys under `~/.config/hiwiski/`:

```sh
cd app && STORE_OUT=build/store flutter test test/store
tool/store_pictures.py app/build/store          # where fastlane looks for them
cd app/android && fastlane metadata check:true  # Play only checks
cd app/android && fastlane metadata
cd app/ios && fastlane metadata version:2026.2.0 screenshots:true
```

What the API cannot set is filled in once in the consoles: the age rating and content
rating, the privacy details and data safety, the category, the review contact.
