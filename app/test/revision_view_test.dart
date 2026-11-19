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
import 'package:hiwiski/core/ui/hiwiski_sheet.dart';
import 'package:hiwiski/data/wiki/wiki_repository.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:hiwiski/features/wiki/page/view/revision_view.dart';

import 'support/fakes.dart';

/// **A version says when it cannot load, and tries again.** The history showed its
/// progress bar forever, offline or after a server error.
void main() {
  testWidgets('a failed load is shown with a retry', (tester) async {
    final wiki = _FakeWiki();
    await tester.pumpWidget(
      ProviderScope(
        // As in the app: a failure shows at once, with "Try again".
        retry: noRetry,
        overrides: [
          wikiRepositoryProvider.overrideWithValue(wiki),
          familyRepositoryProvider.overrideWithValue(NoFamily()),
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHiwiskiSheet<void>(
                  context: context,
                  title: 'History',
                  builder: (_) => const RevisionView(
                    page: _page,
                    revisionId: 'r1',
                    canRestore: false,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('The server had a problem'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(wiki.calls, equals(2));
    expect(find.text('The text of then.'), findsOneWidget);
  });
}

const _page = WikiPage(
  id: 'p1',
  ownerId: 'anna',
  version: 1,
  position: 0,
  kind: 'PAGE',
  title: 'Packing list',
  content: '',
  tags: '',
);

class _FakeWiki implements WikiRepository {
  int calls = 0;

  @override
  Future<Revision> revision(String pageId, String revisionId) async {
    calls++;
    if (calls == 1) throw const HiwiskiFailure(code: FailureCodes.serverError);
    return Revision(
      id: revisionId,
      seq: 1,
      title: 'Packing list',
      createdAt: DateTime(2026, 10, 1),
      kind: .save,
      content: 'The text of then.',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
