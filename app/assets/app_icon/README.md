# App icon sources

The sources of the app icon. Nothing here is bundled into the app (`pubspec.yaml` lists
the asset folders it bundles); the platform folders hold the generated icons.

| File | Use |
|---|---|
| `app_icon_master.svg`, `app_icon_master_2048.png` | Vector master and its raster |
| `app_icon_ios_dark.svg` | Dark variant of the iOS icon |
| `ios_variants_preview.png` | Preview of the iOS light, dark and tinted icons |
| `app_store_icon_1024.png` | App Store Connect |
| `google_play_icon_512.png` | Google Play Console |
| `layers/` | Flat 1024 × 1024 layers for Icon Composer: `light`, `dark`, `tinted_clear_white` |

## Where the icons live

| Platform | Location |
|---|---|
| iOS 26+, macOS 26+ | `ios/Runner/AppIcon.icon`, `macos/Runner/AppIcon.icon` (Liquid Glass, Icon Composer) |
| older iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset` — light, dark, tinted at 1024 px |
| older macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset` — 16 to 1024 px |
| Android | `android/app/src/main/res/mipmap-*` — legacy, round, adaptive and monochrome |
| Web | `web/favicon.png`, `web/icons/` |
| Windows | `windows/runner/resources/app_icon.ico` |
| In the app | `assets/brand/hiwiski_icon.png` — the master at 256 px, the logo on the sign-in and setup screens (`HiwiskiMark`) |
| Website | `site/static/favicon.png`, `site/static/apple-touch-icon.png` — copies of the web build's `web/favicon.png` and `web/icons/Icon-192.png`, so the site's tab looks like the app's |

Both `AppIcon.icon` and the `AppIcon.appiconset` are named `AppIcon`, the value of
`ASSETCATALOG_COMPILER_APPICON_NAME`: Xcode uses the `.icon` where the system supports
Liquid Glass and the asset catalog as the fallback.

## Editing the Liquid Glass icon

Open `ios/Runner/AppIcon.icon` in Icon Composer (Xcode → Open Developer Tool → Icon
Composer). The fill is a gradient #F1F8EC → #C6DEB8; `layer_1_h` and `layer_2_ball` sit
in a group each, with Liquid Glass on. Copy the result to `macos/Runner/AppIcon.icon` as
well — both platforms use the same icon.
