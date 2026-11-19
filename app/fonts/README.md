# Fonts

Roboto, Roboto Mono and Material Symbols Rounded live in the repository as assets and
are **not** loaded via the `google_fonts` package: that package fetches them from
`fonts.gstatic.com` at runtime -- doubly wrong in an app that has to work offline and
makes no third-party calls.

All three are **variable** fonts. Since 2023 Google only ships Roboto and Roboto Mono
that way; static cuts are no longer available there. For the app that means:

* The weight is set via the `wght` axis. `core/theme/hiwiski_theme.dart` therefore sets
  `fontWeight` **and** `fontVariations` on every text style -- without the axis the
  font stays at 400 on some platforms, and without an error message.
* Material Symbols needs the `FILL` axis anyway: `FILL 0` at rest, `FILL 1` for
  selected is the only state indicator on a symbol in the whole design.

License: SIL Open Font License 1.1 (Roboto, Roboto Mono, Noto Color Emoji) and Apache
License 2.0 (Material Symbols). The texts are in `licenses/`; `lib/app/font_licenses.dart` adds them
to the app's license page, since Flutter only collects the licenses of packages.

## Emoji in the web builds

iOS, Android and macOS draw emoji with the system's own emoji font. The web engine
has none and fetches fallback fonts on demand -- by default from `fonts.gstatic.com`,
which the web builds do not call (`web/flutter_bootstrap.js`). It looks for them in
`web/fonts/fallback/` instead, under the exact paths of the engine's own list: the
twelve Noto Color Emoji subsets (about 2 MB together, each loaded only when a page
shows one of its emoji). Other scripts the bundled fonts lack still show as boxes.

The paths belong to the Flutter version. `tool/emoji_fallback.py` reads them from the
SDK and mirrors the files; CI runs it with `--check`, so a Flutter update that moves
them fails the build instead of turning emoji into boxes. After such an update:

    python3 tool/emoji_fallback.py

## Refreshing

    curl -fsSL -o fonts/Roboto.ttf     'https://raw.githubusercontent.com/google/fonts/main/ofl/roboto/Roboto%5Bwdth,wght%5D.ttf'
    curl -fsSL -o fonts/RobotoMono.ttf 'https://raw.githubusercontent.com/google/fonts/main/ofl/robotomono/RobotoMono%5Bwght%5D.ttf'
    curl -fsSL -o fonts/MaterialSymbolsRounded.ttf 'https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf'
    curl -fsSL -o tool/material_symbols_rounded.codepoints 'https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.codepoints'
    python3 tool/generate_symbols.py
    curl -fsSL -o fonts/licenses/Roboto-OFL.txt     'https://raw.githubusercontent.com/google/fonts/main/ofl/roboto/OFL.txt'
    curl -fsSL -o fonts/licenses/RobotoMono-OFL.txt 'https://raw.githubusercontent.com/google/fonts/main/ofl/robotomono/OFL.txt'
    curl -fsSL -o fonts/licenses/MaterialSymbols-LICENSE.txt 'https://raw.githubusercontent.com/google/material-design-icons/master/LICENSE'
    curl -fsSL -o fonts/licenses/NotoColorEmoji-OFL.txt 'https://raw.githubusercontent.com/google/fonts/main/ofl/notocoloremoji/OFL.txt'
