import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/page_header.dart';
import 'package:hiwiski/core/ui/hiwiski_page.dart';
import 'package:hiwiski/components/tags/tags_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/floating_button.dart';

/// The page frame: the filter bar sits in the same place whatever it holds, and a
/// floating button comes with the content, not after it.
const _body = Key('body');

void main() {
  late LocalSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
  });

  Widget page(String title, {PageFilter? filter}) => HiwiskiPage(
    // A subpage header: no avatar, so no session needed.
    header: PageHeader(title: title, onBack: () {}),
    filter: filter,
    body: const SizedBox.expand(key: _body),
  );

  Future<(ProviderContainer, GoRouter)> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        localSettingsProvider.overrideWithValue(settings),
        tagsViewModelProvider.overrideWith(_NoTags.new),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/tasks',
      routes: [
        GoRoute(
          path: '/tasks',
          builder: (context, state) => page('Tasks', filter: _tags()),
          routes: [
            GoRoute(path: 'list', builder: (context, state) => page('List')),
          ],
        ),
        GoRoute(
          path: '/wiki',
          builder: (context, state) => page(
            'Wiki',
            // Like the wiki on the phone with a page open: the bar steps aside.
            filter: _tags(
              visible: !state.uri.queryParameters.containsKey('page'),
            ),
          ),
        ),
        GoRoute(path: '/search', builder: (context, state) => page('Search')),
        GoRoute(
          path: '/start',
          builder: (context, state) => page(
            'Start',
            filter: CustomPageFilter(
              hint: 'Pull',
              bar: OutlinedButton(onPressed: () {}, child: const Text('Edit')),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, router);
  }

  Future<void> go(WidgetTester tester, GoRouter router, String location) async {
    router.go(location);
    await tester.pumpAndSettle();
  }

  // Start's "Customize" is taller than tag chips; the content below may not care.
  testWidgets('the content starts at the same height with any filter bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (_, router) = await pump(tester);
    double bodyTop() => tester.getTopLeft(find.byKey(_body)).dy;

    await go(tester, router, '/wiki');
    final tags = bodyTop();
    await go(tester, router, '/start');
    expect(bodyTop(), equals(tags));
  });

  // The wiki and the board build their content in the place where the loading
  // frame stood. Their floating button must be fully there in the first frame of
  // the content, as it is on screens that use a widget of their own for it.
  testWidgets('the floating button is there in full with the content', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        localSettingsProvider.overrideWithValue(settings),
        tagsViewModelProvider.overrideWith(_NoTags.new),
      ],
    );
    addTearDown(container.dispose);
    final loaded = ValueNotifier(false);
    addTearDown(loaded.dispose);
    final header = PageHeader(title: 'Wiki', onBack: () {});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          home: ValueListenableBuilder(
            valueListenable: loaded,
            builder: (context, loaded, _) => loaded
                ? HiwiskiPage(
                    header: header,
                    body: const SizedBox.expand(key: _body),
                    floatingActionButton: FloatingActionButton.extended(
                      key: _button,
                      onPressed: () {},
                      label: const Text('New page'),
                    ),
                  )
                : HiwiskiPage.loading(header: header),
          ),
        ),
      ),
    );
    // The loading strip runs for as long as it is shown: no pumpAndSettle.
    await tester.pump();

    loaded.value = true;
    await tester.pump();
    expect(find.byKey(_button), findsOneWidget);
    expect(shownInFull(tester, find.byKey(_button)), isTrue);
    await tester.pumpAndSettle();
  });
}

const _button = Key('button');

class _NoTags extends TagsViewModel {
  @override
  Future<TagsState> build() async =>
      const TagsState(ranked: [], recent: [], me: null);
}

TagPageFilter _tags({bool visible = true}) => .new(
  tags: const [],
  selected: const {},
  onToggle: (_) {},
  onClear: () {},
  visible: visible,
);
