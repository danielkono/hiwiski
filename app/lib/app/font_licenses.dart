import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The fonts ship as assets, not as packages (fonts/README.md), so Flutter collects no
/// license for them. Their licenses ask to travel with the font: they are added here,
/// and "Licenses of the packages used" lists them next to the packages.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (fonts, file) in _fontLicenses) {
      yield LicenseEntryWithLineBreaks(
        fonts,
        await rootBundle.loadString(file),
      );
    }
  });
}

const _fontLicenses = [
  (['Roboto'], 'fonts/licenses/Roboto-OFL.txt'),
  (['Roboto Mono'], 'fonts/licenses/RobotoMono-OFL.txt'),
  (['Material Symbols Rounded'], 'fonts/licenses/MaterialSymbols-LICENSE.txt'),
  (['Noto Color Emoji'], 'fonts/licenses/NotoColorEmoji-OFL.txt'),
];
