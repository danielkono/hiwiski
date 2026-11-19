import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/common/theme_preference.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The theme choice first lived only in `LocalSettings` behind a `Provider`.
///
/// That reports no change when something *inside* the held object changes: the switch
/// flipped, the app stayed dark. This is exactly why state which survives a screen
/// change belongs in a notifier.
void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    container = ProviderContainer(
      overrides: [localSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);
  });

  test('without a choice the app follows the system', () {
    expect(
      container.read(preferencesProvider).themeMode,
      equals(ThemePreference.system),
    );
  });

  test('a change reaches the listeners', () async {
    final seen = <ThemePreference>[];
    container.listen(
      preferencesProvider.select((p) => p.themeMode),
      (previous, next) => seen.add(next),
    );

    await container
        .read(preferencesStoreProvider)
        .setThemeMode(ThemePreference.light);

    expect(seen, equals([ThemePreference.light]));
    expect(
      container.read(preferencesProvider).themeMode,
      equals(ThemePreference.light),
    );
  });

  test('it survives a restart', () async {
    await container
        .read(preferencesStoreProvider)
        .setThemeMode(ThemePreference.dark);

    // The first frame after startup should already be right.
    final settings = await LocalSettings.open();
    expect(settings.themeMode, equals(ThemePreference.dark));
  });
}
