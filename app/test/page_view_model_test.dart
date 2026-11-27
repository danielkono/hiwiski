import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/features/wiki/page/page_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **A page is built from what it shows** — a pinboard's page from its map and what
/// that links to, any other page without them.
void main() {
  late HiwiskiDatabase db;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = HiwiskiDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      retry: noRetry,
      overrides: [
        databaseProvider.overrideWithValue(db),
        localSettingsProvider.overrideWithValue(await LocalSettings.open()),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  /// The states [pageId]'s page has been built to, from now on.
  Future<List<PageState?>> watch(String pageId) async {
    final built = <PageState?>[];
    final provider = pageViewModelProvider(pageId);
    final held = container.listen(provider, (_, next) {
      if (next case AsyncData(:final value)) built.add(value);
    });
    addTearDown(held.close);
    await container.read(provider.future);
    // What the page's own sources still had to say.
    await pumpEventQueue();
    built.clear();
    return built;
  }

  test('a page is not built anew for a task list made elsewhere', () async {
    final pageId = await container
        .read(wikiRepositoryProvider)
        .createPage(title: 'Router');
    final built = await watch(pageId);

    await container
        .read(todoRepositoryProvider)
        .createList(name: 'Einkauf', kind: 'STANDARD');
    await pumpEventQueue();

    expect(built, isEmpty);
  });

  test('a pinboard page shows its map', () async {
    final pageId = await container
        .read(wikiRepositoryProvider)
        .createPage(title: 'Urlaub', kind: PageKinds.pinboard);
    await container
        .read(pinboardRepositoryProvider)
        .addNode(
          pageId: pageId,
          kind: PinboardKinds.plain,
          x: 0,
          y: 0,
          width: 100,
          height: 40,
          text: 'Meer',
        );

    final provider = pageViewModelProvider(pageId);
    final held = container.listen(provider, (_, _) {});
    addTearDown(held.close);
    final state = await container.read(provider.future);

    expect(state?.pinboard.nodes.single.text, equals('Meer'));
  });
}
