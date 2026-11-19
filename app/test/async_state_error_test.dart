import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/devices/device_repository.dart';
import 'package:hiwiski/features/devices/view/devices_screen.dart';

import 'support/fakes.dart';

/// **A failed source reaches the screen as its error line, with "Try again".**
/// Riverpod 3 retries a failed provider for some forty seconds and keeps it loading
/// meanwhile; the app turns that off ([noRetry]), so the ViewModel's `build` fails at
/// once and the screen's `when` shows the error.
void main() {
  testWidgets('a failed source shows its error, and "Try again" asks again', (
    tester,
  ) async {
    final devices = _Devices();
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          ...quietSync,
          deviceRepositoryProvider.overrideWithValue(devices),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: const DevicesScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('The server could not be reached.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(devices.asked, equals(2));
    expect(find.text('The server could not be reached.'), findsNothing);
  });
}

/// Offline on the first ask, an empty list on the second.
class _Devices implements DeviceRepository {
  int asked = 0;

  @override
  Stream<List<Device>> watchDevices() => ++asked == 1
      ? .error(const HiwiskiFailure(code: FailureCodes.networkUnreachable))
      : .value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
