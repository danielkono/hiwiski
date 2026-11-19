import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/catalog/catalog_product.dart';
import 'package:hiwiski/data/catalog/catalog_repository.dart';
import 'package:hiwiski/data/todo/todo_repository.dart';
import 'package:hiwiski/features/todo/view/aisle_ui.dart';
import 'package:hiwiski/features/todo/categories/view/categories_screen.dart';
import 'package:hiwiski/features/todo/shopping/view/shopping_aisles.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/features/todo/view/todo_keys.dart';

import 'support/fakes.dart';

/// The category picker, Account → Categories and dragging a shopping row.
void main() {
  late _FakeCatalog catalog;
  late _FakeTodos todos;

  setUp(() {
    todos = _FakeTodos();
    catalog = _FakeCatalog(
      aisles: [
        const CatalogAisle(id: 'produce', key: AisleKeys.produce, position: 0),
        const CatalogAisle(id: 'frozen', key: AisleKeys.frozen, position: 1),
        const CatalogAisle(
          id: 'baby',
          key: AisleKeys.baby,
          position: 2,
          hidden: true,
        ),
        const CatalogAisle(id: 'asia', name: 'Asia shop', position: 3),
      ],
      products: [
        const CatalogProduct(
          id: 'p-soy',
          name: 'Soy sauce',
          aisleId: 'asia',
          usageCount: 0,
        ),
      ],
    );
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...quietSync,
          catalogRepositoryProvider.overrideWithValue(catalog),
          todoRepositoryProvider.overrideWithValue(todos),
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
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester,
    void Function(BuildContext context, WidgetRef ref) onTap,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...quietSync,
          catalogRepositoryProvider.overrideWithValue(catalog),
          todoRepositoryProvider.overrideWithValue(todos),
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
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: TextButton(
                  onPressed: () => onTap(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the picker offers visible categories and moves the product', (
    tester,
  ) async {
    await pump(
      tester,
      (context, ref) => pickAisle(
        context,
        createAisle: catalog.createAisle,
        assignAisle: catalog.assignAisle,
        at: .zero,
        productName: 'Peas',
        current: null,
        aisles: catalog.aisles,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Fruit & vegetables'), findsOneWidget);
    expect(find.text('Asia shop'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    // Hidden: not offered.
    expect(find.text('Baby'), findsNothing);

    await tester.tap(find.text('Frozen'));
    await tester.pumpAndSettle();
    expect(catalog.assigned, equals([('Peas', 'frozen')]));
  });

  testWidgets('"New category…" creates one and puts the product in it', (
    tester,
  ) async {
    await pump(
      tester,
      (context, ref) => pickAisle(
        context,
        createAisle: catalog.createAisle,
        assignAisle: catalog.assignAisle,
        at: .zero,
        productName: 'Tofu',
        current: null,
        aisles: catalog.aisles,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New category…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(TodoKeys.aisleName), 'Organic shop');
    await tester.tap(find.byKey(TodoKeys.aisleNameSave));
    await tester.pumpAndSettle();

    expect(catalog.created, equals(['Organic shop']));
    expect(catalog.assigned, equals([('Tofu', 'new-1')]));
  });

  testWidgets('offline the picker says categories need a connection', (
    tester,
  ) async {
    catalog.offline = true;
    await pump(
      tester,
      (context, ref) => pickAisle(
        context,
        createAisle: catalog.createAisle,
        assignAisle: catalog.assignAisle,
        at: .zero,
        productName: 'Peas',
        current: null,
        aisles: catalog.aisles,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frozen'));
    await tester.pumpAndSettle();

    expect(find.text('Categories can only be changed online.'), findsOneWidget);
  });

  testWidgets('Account → Categories hides built-in ones and deletes own ones', (
    tester,
  ) async {
    await pumpPage(tester, const CategoriesScreen());

    expect(find.text('Baby · hidden'), findsOneWidget);
    // Built-in ones cannot be deleted, own ones cannot be hidden.
    expect(find.byKey(TodoKeys.aisleDelete('produce')), findsNothing);
    expect(find.byKey(TodoKeys.aisleHide('asia')), findsNothing);

    await tester.tap(find.byKey(TodoKeys.aisleHide('produce')));
    await tester.pumpAndSettle();
    expect(catalog.hidden, equals([('produce', true)]));
    expect(find.text('Fruit & vegetables · hidden'), findsOneWidget);

    await tester.tap(find.byKey(TodoKeys.aisleDelete('asia')));
    await tester.pumpAndSettle();
    expect(
      find.text('1 product in “Asia shop” moves to “Other”.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(TodoKeys.aisleDeleteConfirm));
    await tester.pumpAndSettle();
    expect(catalog.deleted, equals(['asia']));
    expect(find.text('Asia shop'), findsNothing);
  });

  testWidgets('Account → Categories shows, adds and moves the assignments', (
    tester,
  ) async {
    await pumpPage(tester, const CategoriesScreen());

    // Closed: no products. Open: its chips and a field to add one.
    expect(find.byKey(TodoKeys.categoryProduct('p-soy')), findsNothing);
    await tester.tap(find.text('Asia shop'));
    await tester.pumpAndSettle();
    expect(find.byKey(TodoKeys.categoryProduct('p-soy')), findsOneWidget);

    await tester.enterText(
      find.byKey(TodoKeys.categoryAddProduct('asia')),
      'Kimchi',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(catalog.assigned, equals([('Kimchi', 'asia')]));

    // A tap on a chip moves the product elsewhere.
    await tester.tap(find.byKey(TodoKeys.categoryProduct('p-soy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TodoKeys.aisleOption('frozen')));
    await tester.pumpAndSettle();
    expect(catalog.assigned.last, equals(('Soy sauce', 'frozen')));
  });

  testWidgets('a search opens every category with a hit', (tester) async {
    await pumpPage(tester, const CategoriesScreen());

    await tester.enterText(find.byKey(TodoKeys.categorySearch), 'soy');
    await tester.pumpAndSettle();
    expect(find.byKey(TodoKeys.categoryProduct('p-soy')), findsOneWidget);
  });

  testWidgets('Account → Categories moves a category by a long press', (
    tester,
  ) async {
    await pumpPage(tester, const CategoriesScreen());
    final produce = find.byKey(TodoKeys.categoryCard('produce'));
    final gesture = await tester.startGesture(
      tester.getTopLeft(produce) + const Offset(150, 24),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // Down past the next row: produce no longer comes first.
    final frozen = tester.getRect(find.byKey(TodoKeys.categoryCard('frozen')));
    await gesture.moveTo(Offset(150, frozen.bottom + 4));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final order = catalog.reordered.single;
    expect(order.first, equals('frozen'));
    expect(order.indexOf('produce'), greaterThan(0));
    // And it stays where it was dropped once the catalog publishes the new order.
    expect(
      tester.getTopLeft(find.byKey(TodoKeys.categoryCard('frozen'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(TodoKeys.categoryCard('produce'))).dy,
      ),
    );
  });

  testWidgets('Account → Categories scrolls near the edge while moving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    catalog.aisles = [
      for (var i = 0; i < 20; i++)
        CatalogAisle(id: 'own-$i', name: 'Own $i', position: i),
    ];
    await pumpPage(tester, const CategoriesScreen());
    final page = tester.state<ScrollableState>(find.byType(Scrollable).first);

    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(TodoKeys.categoryCard('own-0'))) +
          const Offset(150, 24),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(const Offset(150, 495));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      // The pointer stays, as a thumb at the edge would.
      await gesture.moveBy(Offset.zero);
    }

    expect(page.position.pixels, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  group('dragging a shopping row', () {
    Widget aisles(List<Todo> items) => ShoppingAisles(
      items: items,
      products: catalog.products,
      aisles: catalog.aisles,
      movable: true,
      onAssignAisle: catalog.assignAisle,
      onReposition: todos.reposition,
      rowBuilder: (todo) => SizedBox(
        height: 48,
        child: Text(todo.title, key: ValueKey('row-${todo.id}')),
      ),
    );

    /// Holds a row — by touch after a long press, the test runs as Android.
    Future<TestGesture> hold(WidgetTester tester, String id) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('row-$id'))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      return gesture;
    }

    Future<void> dropOn(
      WidgetTester tester,
      TestGesture gesture,
      Finder target,
    ) async {
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('into a category of the list moves the product', (
      tester,
    ) async {
      await pumpPage(
        tester,
        aisles([_todo('t-1', 'Soy sauce'), _todo('t-2', 'Apples')]),
      );
      final gesture = await hold(tester, 't-1');

      await dropOn(
        tester,
        gesture,
        find.byKey(TodoKeys.shoppingAisle('other')),
      );

      expect(catalog.assigned, equals([('Soy sauce', null)]));
    });

    testWidgets('holding changes nothing; "Other category" opens the rest', (
      tester,
    ) async {
      await pumpPage(
        tester,
        aisles([_todo('t-1', 'Soy sauce'), _todo('t-2', 'Apples')]),
      );
      final asia = tester.getTopLeft(
        find.byKey(TodoKeys.shoppingAisle('asia')),
      );
      final gesture = await hold(tester, 't-1');

      // No empty categories between the ones in the list, nothing moved.
      expect(find.byKey(TodoKeys.shoppingAisle('frozen')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(TodoKeys.shoppingAisle('asia'))),
        equals(asia),
      );

      // Below the list one more target; held over it, the rest opens.
      await gesture.moveTo(
        tester.getCenter(find.byKey(TodoKeys.shoppingOtherAisles)),
      );
      await tester.pump();
      expect(find.byKey(TodoKeys.shoppingAisle('produce')), findsOneWidget);
      // Hidden ones stay hidden, and "Other" is in the list already.
      expect(find.byKey(TodoKeys.shoppingAisle('baby')), findsNothing);
      expect(find.byKey(TodoKeys.shoppingAisle('other')), findsOneWidget);

      await dropOn(
        tester,
        gesture,
        find.byKey(TodoKeys.shoppingAisle('frozen')),
      );

      expect(catalog.assigned, equals([('Soy sauce', 'frozen')]));
      expect(find.byKey(TodoKeys.shoppingOtherAisles), findsNothing);
    });

    testWidgets('onto a row of its category sorts it there', (tester) async {
      await pumpPage(
        tester,
        aisles([
          _todo('t-1', 'Apples'),
          _todo('t-2', 'Bread'),
          _todo('t-3', 'Cheese'),
        ]),
      );
      final gesture = await hold(tester, 't-1');

      // The lower half of "Cheese": after it.
      final cheese = tester.getRect(find.byKey(TodoKeys.shoppingRow('t-3')));
      await gesture.moveTo(Offset(cheese.center.dx, cheese.bottom - 6));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final (item, others, at) = todos.repositioned.single;
      expect(item.id, equals('t-1'));
      expect([for (final row in others) row.id], equals(['t-2', 't-3']));
      expect(at, equals(2));
      // Within its category the catalog stays as it is.
      expect(catalog.assigned, isEmpty);
    });

    testWidgets(
      'onto a row of another category moves it there, at that place',
      (tester) async {
        await pumpPage(
          tester,
          aisles([
            _todo('t-1', 'Soy sauce'),
            _todo('t-2', 'Apples'),
            _todo('t-3', 'Bread'),
          ]),
        );
        final gesture = await hold(tester, 't-1');

        // The upper half of "Bread", in "Other": before it.
        final bread = tester.getRect(find.byKey(TodoKeys.shoppingRow('t-3')));
        await gesture.moveTo(Offset(bread.center.dx, bread.top + 6));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(catalog.assigned, equals([('Soy sauce', null)]));
        final (item, others, at) = todos.repositioned.single;
        expect(item.id, equals('t-1'));
        expect([for (final row in others) row.id], equals(['t-2', 't-3']));
        expect(at, equals(1));
      },
    );

    testWidgets('offline it stays where it was', (tester) async {
      catalog.offline = true;
      await pumpPage(
        tester,
        aisles([_todo('t-1', 'Soy sauce'), _todo('t-2', 'Apples')]),
      );
      final gesture = await hold(tester, 't-1');

      await dropOn(tester, gesture, find.byKey(TodoKeys.shoppingRow('t-2')));

      expect(todos.repositioned, isEmpty);
    });

    testWidgets('as a sliver, a category is built when it comes into view', (
      tester,
    ) async {
      await pumpPage(
        tester,
        SizedBox(
          height: 60,
          child: CustomScrollView(
            // Nothing built ahead of time: what is built is what is in view.
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            slivers: [
              ShoppingAisles(
                items: [
                  _todo('t-soy', 'Soy sauce'),
                  for (var i = 0; i < 30; i++) _todo('t-$i', 'Item $i'),
                ],
                products: catalog.products,
                aisles: catalog.aisles,
                movable: true,
                sliver: true,
                onAssignAisle: catalog.assignAisle,
                onReposition: todos.reposition,
                rowBuilder: (todo) =>
                    SizedBox(height: 48, child: Text(todo.title)),
              ),
            ],
          ),
        ),
      );

      // The Asia shop fills the view; "Other", below it, is not built yet.
      expect(find.byKey(TodoKeys.shoppingAisle('asia')), findsOneWidget);
      expect(
        find.byKey(TodoKeys.shoppingAisle('other'), skipOffstage: false),
        findsNothing,
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.byKey(TodoKeys.shoppingAisle('other')), findsOneWidget);
    });

    testWidgets('near the bottom edge the list scrolls by itself', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpPage(
        tester,
        SizedBox(
          height: 300,
          child: ListView(
            controller: scroll,
            children: [
              aisles([for (var i = 0; i < 20; i++) _todo('t-$i', 'Item $i')]),
            ],
          ),
        ),
      );
      final gesture = await hold(tester, 't-0');

      await gesture.moveTo(const Offset(100, 290));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(scroll.offset, greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}

Todo _todo(String id, String title) => .new(
  id: id,
  ownerId: 'anna',
  version: 1,
  listId: 'list',
  title: title,
  status: TodoStatuses.open,
  assignees: '',
  tags: '',
  position: 0,
);

/// The catalogue without a server: records what the screens ask for — and, like the
/// real repository writing into Drift, publishes every change, the categories in
/// their order and the products of a deleted one without it.
class _FakeCatalog implements CatalogRepository {
  _FakeCatalog({required this.aisles, required this.products});

  List<CatalogAisle> aisles;
  List<CatalogProduct> products;
  final _aisleChanges = StreamController<List<CatalogAisle>>.broadcast();
  final _productChanges = StreamController<List<CatalogProduct>>.broadcast();

  static CatalogAisle _with(
    CatalogAisle aisle, {
    String? name,
    int? position,
    bool? hidden,
  }) => .new(
    id: aisle.id,
    key: aisle.key,
    name: name ?? aisle.name,
    position: position ?? aisle.position,
    hidden: hidden ?? aisle.hidden,
  );

  @override
  Future<void> carryOver() async {}

  bool offline = false;
  final assigned = <(String, String?)>[];
  final created = <String>[];
  final hidden = <(String, bool)>[];
  final deleted = <String>[];

  void _check() {
    if (offline) throw const HiwiskiFailure.network();
  }

  void _publish(List<CatalogAisle> next) {
    aisles = [...next]..sort((a, b) => a.position.compareTo(b.position));
    _aisleChanges.add(aisles);
  }

  @override
  Future<void> refresh() async {}

  @override
  Stream<List<CatalogProduct>> watch() async* {
    yield products;
    yield* _productChanges.stream;
  }

  @override
  Stream<List<CatalogAisle>> watchAisles() async* {
    yield aisles;
    yield* _aisleChanges.stream;
  }

  @override
  Future<void> assignAisle(String productName, String? aisleId) async {
    _check();
    assigned.add((productName, aisleId));
  }

  @override
  Future<CatalogAisle> createAisle(String name) async {
    _check();
    created.add(name);
    final aisle = CatalogAisle(
      id: 'new-${created.length}',
      name: name,
      position: aisles.length,
    );
    _publish([...aisles, aisle]);
    return aisle;
  }

  @override
  Future<void> setAisleHidden(String id, bool value) async {
    _check();
    hidden.add((id, value));
    _publish([
      for (final aisle in aisles)
        aisle.id == id ? _with(aisle, hidden: value) : aisle,
    ]);
  }

  @override
  Future<void> deleteAisle(String id) async {
    _check();
    deleted.add(id);
    _publish([
      for (final aisle in aisles)
        if (aisle.id != id) aisle,
    ]);
    // Its products lose their category, as on the server.
    products = [
      for (final product in products)
        product.aisleId == id
            ? CatalogProduct(
                id: product.id,
                name: product.name,
                defaultUnit: product.defaultUnit,
                usageCount: product.usageCount,
              )
            : product,
    ];
    _productChanges.add(products);
  }

  @override
  Future<void> renameAisle(String id, String name) async {
    _check();
    _publish([
      for (final aisle in aisles)
        aisle.id == id ? _with(aisle, name: name) : aisle,
    ]);
  }

  @override
  Future<void> reorderAisles(List<String> ids) async {
    _check();
    reordered.add(ids);
    final order = [
      ...ids,
      for (final aisle in aisles)
        if (!ids.contains(aisle.id)) aisle.id,
    ];
    _publish([
      for (final aisle in aisles)
        _with(aisle, position: order.indexOf(aisle.id)),
    ]);
  }

  final reordered = <List<String>>[];
}

/// The tasks without a database: records where rows are put.
class _FakeTodos implements TodoRepository {
  final repositioned = <(Todo, List<Todo>, int)>[];

  @override
  Future<void> reposition(
    Todo item, {
    required List<Todo> others,
    required int at,
  }) async => repositioned.add((item, others, at));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
