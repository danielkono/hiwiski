import 'package:flutter/material.dart';

import '../common/theme_preference.dart';

/// The member's theme choice in Flutter's terms, and back.
extension ThemePreferenceMode on ThemePreference {
  ThemeMode get mode => switch (this) {
    .light => ThemeMode.light,
    .dark => ThemeMode.dark,
    .system => ThemeMode.system,
  };
}

extension ThemeModePreference on ThemeMode {
  ThemePreference get preference => switch (this) {
    .light => ThemePreference.light,
    .dark => ThemePreference.dark,
    .system => ThemePreference.system,
  };
}
