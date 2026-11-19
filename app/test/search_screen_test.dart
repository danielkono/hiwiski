import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_symbols.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/search/search_models.dart';
import 'package:hiwiski/data/search/search_repository.dart';
import 'package:hiwiski/features/search/view/search_keys.dart';
import 'package:hiwiski/features/search/view/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the search screen shows answers the term in the field — no other.
void main() {
  late _FakeSearch search;

  Future<void> pump(WidgetTester tester) async {
    search = _FakeSearch();
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchRepositoryProvider.overrideWithValue(search),
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(settings),
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
          home: const SearchScreen(),
        ),
      ),
    );
    // The screen shows once its state has loaded.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  // "kin" answered after "kinder" and its hits stood under "kinder".
  testWidgets('a slow answer to an older term is dropped', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(SearchKeys.searchInput), 'kin');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(SearchKeys.searchInput), 'kinder');
    await tester.pump(const Duration(milliseconds: 300));

    search.answer('kinder', 'Kinderarzt');
    // The ViewModel rebuilds its state asynchronously.
    await tester.pump();
    await tester.pump();
    search.answer('kin', 'Kinokarten');
    // The ViewModel rebuilds its state asynchronously.
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Kinderarzt'), findsWidgets);
    expect(find.textContaining('Kinokarten'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('clearing drops the term still waiting', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(SearchKeys.searchInput), 'arzt');
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(HiwiskiSymbols.close));
    await tester.pump(const Duration(milliseconds: 300));

    expect(search.asked, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  // A 500 escaped from the timer; the previous term's hits stayed as the answer.
  testWidgets('a failed search says so instead of showing old hits', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(SearchKeys.searchInput), 'kin');
    await tester.pump(const Duration(milliseconds: 300));
    search.answer('kin', 'Kinokarten');
    // The ViewModel rebuilds its state asynchronously.
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byKey(SearchKeys.searchInput), 'kino');
    await tester.pump(const Duration(milliseconds: 300));
    search.fail('kino');
    // The ViewModel rebuilds its state asynchronously.
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Kinokarten'), findsNothing);
    expect(find.textContaining('The server had a problem'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}

class _FakeSearch implements SearchRepository {
  final _pending = <String, Completer<SearchOutcome>>{};

  Iterable<String> get asked => _pending.keys;

  void fail(String term) => _pending[term]!.completeError(
    const HiwiskiFailure(code: FailureCodes.serverError),
  );

  void answer(String term, String title) => _pending[term]!.complete(
    SearchOutcome(
      hits: [SearchHitView(itemType: 'TODO', itemId: term, title: title)],
      offline: false,
    ),
  );

  @override
  Future<SearchOutcome> search(
    String query, {
    Set<String> types = const {},
    bool includeArchived = false,
  }) => (_pending[query] = Completer<SearchOutcome>()).future;

  @override
  Future<Map<String, ({String tags, bool recipe})>> facts(
    List<SearchHitView> hits,
  ) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
