import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/assignees/view/assignees_section.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';

import 'support/fakes.dart';

/// **Assignees the device cannot name are still shown.** Offline, the members did
/// not load, and a task with assignees said "Nobody assigned".
void main() {
  testWidgets('an assignee that is not loaded is not "nobody"', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [familyRepositoryProvider.overrideWithValue(_Offline())],
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
          home: const Scaffold(body: AssigneesSection(assignees: ['m1'])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nobody'), findsNothing);
    expect(find.text('Someone not loaded here'), findsOneWidget);
  });
}

/// Offline: the members do not load; the groups are known.
class _Offline extends NoFamily {
  @override
  Stream<List<Member>> watchMembers() =>
      .error(const HiwiskiFailure(code: FailureCodes.networkUnreachable));
}
