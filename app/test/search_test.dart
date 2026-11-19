import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/domain/search/search_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/data/search/search_repository.dart';

import 'support/fakes.dart';

/// The client-side half of search.
///
/// "**Both halves must answer the same question the same way**; in an earlier version the device
/// did not find 'Termin' when you typed 'Termine', but the server did."
void main() {
  group('highlighting', () {
    test('finds the match in the middle of a sentence', () {
      expect(highlightRanges('Kinderarzt anrufen', 'arzt'), equals([(6, 10)]));
    });

    test('ignores upper and lower case', () {
      // Whoever types "kinder" also means "Kinder".
      expect(highlightRanges('Kinderarzt', 'kinder'), equals([(0, 6)]));
    });

    test('finds several occurrences', () {
      expect(
        highlightRanges('Milch und Milch', 'milch'),
        equals([(0, 5), (10, 15)]),
      );
    });

    // On the web "İ" lowercases to two code units, and the ranges ran past the
    // text. Wherever this runs, they stay inside it.
    test('ranges stay inside the text', () {
      const text = 'İzmir kin';
      for (final (_, end) in highlightRanges(text, 'kin')) {
        expect(end, lessThanOrEqualTo(text.length));
      }
    });

    test('no match, no range', () {
      expect(highlightRanges('Kinderarzt', 'zahn'), isEmpty);
      expect(highlightRanges('Kinderarzt', '   '), isEmpty);
    });
  });

  group('offline over what is on the device', () {
    late HiwiskiDatabase db;

    setUp(() async {
      db = HiwiskiDatabase(NativeDatabase.memory());
      await db
          .into(db.todos)
          .insert(
            TodosCompanion.insert(
              id: 't1',
              ownerId: 'anna',
              listId: 'l1',
              title: const Value('Kinderarzt anrufen'),
              description: const Value('Wegen der Impfung'),
              entityKey: const Value('TD-1'),
            ),
          );
      await db
          .into(db.wikiPages)
          .insert(
            WikiPagesCompanion.insert(
              id: 'p1',
              ownerId: 'anna',
              title: const Value('Router'),
              content: const Value('Die IP ist 192.168.1.1.'),
            ),
          );
    });

    tearDown(() => db.close());

    test('"kin" matches while typing', () async {
      final rows = await (db.select(
        db.todos,
      )..where((row) => row.title.lower().like('%kin%'))).get();
      expect(rows.single.title, equals('Kinderarzt anrufen'));
    });

    test('"kinder" finds "Kinderarzt"', () async {
      // No stemmer splits German compounds — and SQLite does not ship a German one
      // anyway. The word fragment carries this case on both sides.
      final rows = await (db.select(
        db.todos,
      )..where((row) => row.title.lower().like('%kinder%'))).get();
      expect(rows, hasLength(1));
    });

    test('the text of a wiki page is searched too', () async {
      final rows = await (db.select(
        db.wikiPages,
      )..where((row) => row.content.lower().like('%192.168%'))).get();
      expect(rows.single.title, equals('Router'));
    });

    test('deleted items are not found', () async {
      await (db.update(db.todos)..where((row) => row.id.equals('t1'))).write(
        TodosCompanion(deletedAt: Value(DateTime.now())),
      );

      final rows =
          await (db.select(db.todos)
                ..where((row) => row.deletedAt.isNull())
                ..where((row) => row.title.lower().like('%kinder%')))
              .get();
      expect(rows, isEmpty);
    });
  });

  group('the repository offline', () {
    late HiwiskiDatabase db;
    late SearchRepository repository;

    setUp(() async {
      db = HiwiskiDatabase(NativeDatabase.memory());
      final api = HiwiskiApi(
        tokens: NoTokens(),
        baseUrl: 'http://hiwiski.test',
      );
      api.dio.httpClientAdapter = _Offline();
      repository = SearchRepository(db: db, api: api, serverless: false);
      for (final (id, title) in [
        ('t1', 'Rabatt 100% nutzen'),
        ('t2', 'Kinderarzt anrufen'),
        ('t3', 'a_b testen'),
        ('t4', 'axb testen'),
        ('t5', 'Übung abmelden'),
      ]) {
        await db
            .into(db.todos)
            .insert(
              TodosCompanion.insert(
                id: id,
                ownerId: 'anna',
                listId: 'l1',
                title: Value(title),
              ),
            );
      }
    });

    tearDown(() => db.close());

    Future<List<String>> titles(String query) async => [
      for (final hit in (await repository.search(query)).hits) hit.title,
    ];

    // As on the server: what was typed, not wildcards.
    test('"%" and "_" are text', () async {
      expect(await titles('%'), equals(['Rabatt 100% nutzen']));
      expect(await titles('a_b'), equals(['a_b testen']));
    });

    // The Tasks screen filters by the list's tags; search took only the task's own.
    test("a task's facts carry its list's tags", () async {
      await db
          .into(db.todoLists)
          .insert(
            TodoListsCompanion.insert(
              id: 'l1',
              ownerId: 'anna',
              name: const Value('Office'),
              tags: const Value('work'),
            ),
          );
      final hits = (await repository.search('Kinderarzt')).hits;

      final facts = await repository.facts(hits);

      expect(facts['t2']?.tags, equals('work'));
    });

    // SQLite's lower() folds ASCII only: "Übung" was not found as "übung" offline,
    // while the server found it.
    test('capital umlauts are matched too', () async {
      expect(await titles('übung'), equals(['Übung abmelden']));
    });
  });

  group('outcome', () {
    test('offline is not an error but a piece of information', () {
      const outcome = SearchOutcome(hits: [], offline: true);
      // An empty result then means "not found here" and not "does not exist".
      expect(outcome.offline, isTrue);
      expect(outcome.hits, isEmpty);
    });
  });
}

/// No server: the search falls back to the device.
class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: 'offline',
  );

  @override
  void close({bool force = false}) {}
}
