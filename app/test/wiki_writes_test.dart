import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';

import 'support/fakes.dart';

import 'package:hiwiski/features/wiki/area/wiki_area_view_model.dart';

/// Writes to wiki pages that have to hold up against what the device sees meanwhile.
void main() {
  // Two devices moving pages in opposite directions offline can build a parent
  // cycle; the delete walked it forever, and nothing was deleted.
  test('deleting a page in a parent cycle deletes both', () async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      ],
    );
    addTearDown(container.dispose);
    final wiki = container.read(wikiRepositoryProvider);
    final b = await wiki.createPage(title: 'B');
    final c = await wiki.createPage(title: 'C', parentId: b);
    // What two offline moves leave behind: B under C, C under B.
    await (db.update(db.wikiPages)..where((row) => row.id.equals(b))).write(
      WikiPagesCompanion(parentId: Value(c)),
    );
    final WikiPage? page = await container
        .read(wikiRepositoryProvider)
        .watchPage(b)
        .first;

    await wiki.deletePage(page!);

    final rows = await db.select(db.wikiPages).get();
    expect(rows.every((row) => row.deletedAt != null), isTrue);
  });

  // Two quick taps both started from the content the screen showed; the second
  // write took the first tick back.
  test('two quick ticks from one snapshot both stay', () async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      ],
    );
    addTearDown(container.dispose);
    final wiki = container.read(wikiRepositoryProvider);
    final id = await wiki.createPage(title: 'Packing');
    final WikiPage? created = await container
        .read(wikiRepositoryProvider)
        .watchPage(id)
        .first;
    await wiki.updatePage(created!, content: '- [ ] passport\n- [ ] tickets');
    await Future<void>.delayed(Duration.zero);
    final WikiPage? snapshot = await container
        .read(wikiRepositoryProvider)
        .watchPage(id)
        .first;

    await Future.wait([
      wiki.toggleTaskAt(snapshot!, 0),
      wiki.toggleTaskAt(snapshot, 1),
    ]);

    final row = await (db.select(
      db.wikiPages,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(row.content, equals('- [x] passport\n- [x] tickets'));
  });

  // A drop writes the moved page and only the siblings that had to make room — and
  // a new parent in the same mutation as the position.
  test('a drop into another page moves it there, with its position', () async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      ],
    );
    addTearDown(container.dispose);
    final wiki = container.read(wikiRepositoryProvider);
    final house = await wiki.createPage(title: 'House');
    final garden = await wiki.createPage(title: 'Garden');
    final pages = await wiki.watchPages().first;
    final byId = {for (final page in pages) page.id: page};

    await wiki.arrangePages(
      moved: byId[garden]!,
      parentId: house,
      positions: {garden: 0},
      siblings: [byId[garden]!],
    );

    final moved = await wiki.watchPage(garden).first;
    expect(moved?.parentId, equals(house));
  });

  test('the wiki area drops a page where it was dropped', () async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      ],
    );
    addTearDown(container.dispose);
    final wiki = container.read(wikiRepositoryProvider);
    final a = await wiki.createPage(title: 'A');
    final b = await wiki.createPage(title: 'B');
    final subscription = container.listen(wikiAreaViewModelProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(wikiAreaViewModelProvider.future);

    final outcome = await container
        .read(wikiAreaViewModelProvider.notifier)
        .drop(a, b, .after);
    await pumpEventQueue();

    expect(outcome, equals(DropOutcome.moved));
    final state = await container.read(wikiAreaViewModelProvider.future);
    expect(state.tree.map((node) => node.page.title), equals(['B', 'A']));

    final inside = await container
        .read(wikiAreaViewModelProvider.notifier)
        .drop(b, a, .inside);
    await pumpEventQueue();
    expect(inside, equals(DropOutcome.moved));
    final nested = await container.read(wikiAreaViewModelProvider.future);
    expect(nested.tree.single.page.title, equals('A'));
    expect(nested.tree.single.children.single.page.title, equals('B'));
  });

  // Shared to read only: the drop changes nothing and says so.
  test('a drop that would change a read-only page is refused', () async {
    SharedPreferences.setMockInitialValues({});
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = HiwiskiApi(tokens: NoTokens(), baseUrl: 'http://hiwiski.test');
    api.dio.httpClientAdapter = _ReadOnlyShares();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
        hiwiskiApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final wiki = container.read(wikiRepositoryProvider);
    final a = await wiki.createPage(title: 'A');
    final b = await wiki.createPage(title: 'B');
    final subscription = container.listen(wikiAreaViewModelProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(wikiAreaViewModelProvider.future);
    await pumpEventQueue();

    final state = await container.read(wikiAreaViewModelProvider.future);
    expect(state.movable, isEmpty);
    final outcome = await container
        .read(wikiAreaViewModelProvider.notifier)
        .drop(a, b, .inside);

    expect(outcome, equals(DropOutcome.notAllowed));
    expect((await wiki.watchPage(a).first)?.parentId, isNull);
  });
}

/// Every share sheet says *read*; anything else is offline.
class _ReadOnlyShares implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (!path.endsWith('/shares')) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final parts = path.split('/');
    return .fromString(
      jsonEncode({
        'itemType': parts[parts.length - 3],
        'itemId': parts[parts.length - 2],
        'entries': <Object>[],
        'mayEdit': false,
        'myLevel': 'READ',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
