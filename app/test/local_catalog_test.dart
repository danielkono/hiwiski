import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/data/catalog/catalog_repository.dart';
import 'package:hiwiski/domain/catalog/catalog_product.dart';
import 'package:hiwiski/domain/catalog/catalog_seed.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// The shopping categories of a device without a server, and how they reach the
/// server it connects to.
void main() {
  late HiwiskiDatabase db;
  late LocalSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await LocalSettings.open();
    db = HiwiskiDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  CatalogRepository local() => .new(
    db: db,
    api: HiwiskiApi(tokens: NoTokens()),
    settings: settings,
    serverless: true,
    seed: () async => File('assets/catalog/products-de.tsv').readAsString(),
  );

  test('the device starts from the very seed the server starts from', () {
    for (final language in ['de', 'en']) {
      expect(
        File('assets/catalog/products-$language.tsv').readAsStringSync(),
        equals(
          File(
            '../server/app/src/main/resources/catalog/products-$language.tsv',
          ).readAsStringSync(),
        ),
        reason: 'products-$language.tsv differs from the server copy',
      );
    }
  });

  test('the seed reads names, categories and units, and skips comments', () {
    final products = parseCatalogSeed(
      '# a comment\n'
      'Äpfel\tproduce\tkg\n'
      '\n'
      'Bananen\tproduce\n',
    );
    expect(products, hasLength(2));
    expect(products.first.name, equals('Äpfel'));
    expect(products.first.aisleKey, equals('produce'));
    expect(products.first.defaultUnit, equals('kg'));
    expect(products.last.defaultUnit, isNull);
  });

  test('without a server the catalogue is seeded once, in order', () async {
    final catalog = local();
    await catalog.refresh();
    await catalog.refresh();

    final aisles = await catalog.watchAisles().first;
    expect(aisles.map((aisle) => aisle.key), equals(AisleKeys.all));
    final products = await catalog.watch().first;
    final apples = products.singleWhere((product) => product.name == 'Äpfel');
    expect(
      apples.aisleId,
      equals(aisles.singleWhere((a) => a.key == 'produce').id),
    );
  });

  test('without a server the server rules hold on the device', () async {
    final catalog = local();
    await catalog.refresh();
    final own = await catalog.createAisle(' Asia shop ');
    expect(own.name, equals('Asia shop'));
    expect(own.position, equals(AisleKeys.all.length));

    await expectLater(
      catalog.createAisle('asia SHOP'),
      throwsA(
        isA<HiwiskiFailure>().having(
          (f) => f.code,
          'code',
          FailureCodes.catalogAisleNameTaken,
        ),
      ),
    );
    final produce = (await catalog.watchAisles().first).first;
    await expectLater(
      catalog.renameAisle(produce.id, 'Obst'),
      throwsA(isA<HiwiskiFailure>()),
    );

    await catalog.assignAisle('kimchi', own.id);
    await catalog.assignAisle('Kimchi', produce.id);
    final kimchi = (await catalog.watch().first).where(
      (product) => product.name.toLowerCase() == 'kimchi',
    );
    expect(kimchi, hasLength(1));
    expect(kimchi.single.aisleId, equals(produce.id));

    await catalog.reorderAisles([own.id]);
    expect((await catalog.watchAisles().first).first.id, equals(own.id));

    await catalog.deleteAisle(own.id);
    expect(
      (await catalog.watchAisles().first).map((aisle) => aisle.id),
      isNot(contains(own.id)),
    );
  });

  test(
    'connected, its own categories and assignments go to the server',
    () async {
      final catalog = local();
      await catalog.refresh();
      final own = await catalog.createAisle('Asia shop');
      final aisles = await catalog.watchAisles().first;
      final frozen = aisles.singleWhere((aisle) => aisle.key == 'frozen');
      await catalog.setAisleHidden(frozen.id, true);
      await catalog.assignAisle('Kimchi', own.id);
      await settings.setCatalogCarryover(true);

      final server = _CatalogServer();
      final api = HiwiskiApi(
        tokens: NoTokens(),
        baseUrl: 'http://hiwiski.test',
      );
      api.dio.httpClientAdapter = server;
      final connected = CatalogRepository(
        db: db,
        api: api,
        settings: settings,
        serverless: false,
        seed: () async => '',
      );

      await connected.refresh();

      expect(server.created, equals(['Asia shop']));
      expect(server.hidden, equals({'server-frozen': true}));
      expect(server.assigned, equals({'Kimchi': 'server-own'}));
      expect(server.order.first, equals('server-produce'));
      expect(server.order, contains('server-own'));
      expect(settings.catalogCarryover, isFalse);
      // The server's catalogue replaced the device's.
      expect(
        (await connected.watchAisles().first).map((aisle) => aisle.id),
        everyElement(startsWith('server-')),
      );
    },
  );
}

/// The server's catalogue: the built-in categories, and what the device sends.
class _CatalogServer implements HttpClientAdapter {
  final created = <String>[];
  final hidden = <String, bool>{};
  final assigned = <String, String?>{};
  List<String> order = [];

  late final _aisles = <Map<String, Object?>>[
    for (final (position, key) in AisleKeys.all.indexed)
      {'id': 'server-$key', 'key': key, 'position': position, 'hidden': false},
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final body = switch (options.data) {
      null => const <String, dynamic>{},
      final data => jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
    };
    if (options.method == 'GET' && path.endsWith('/catalog/aisles')) {
      return _json({'aisles': _aisles});
    }
    if (options.method == 'GET' && path.endsWith('/catalog/products')) {
      return _json({'products': <Object>[]});
    }
    if (options.method == 'POST' && path.endsWith('/catalog/aisles')) {
      final name = body['name'] as String;
      created.add(name);
      final aisle = {
        'id': 'server-own',
        'name': name,
        'position': _aisles.length,
        'hidden': false,
      };
      _aisles.add(aisle);
      return _json(aisle, 201);
    }
    if (path.endsWith('/catalog/aisles/order')) {
      order = (body['ids'] as List<dynamic>).cast<String>();
      return _json({'aisles': _aisles});
    }
    if (options.method == 'PATCH' && path.contains('/catalog/aisles/')) {
      final id = path.split('/').last;
      hidden[id] = body['hidden'] as bool;
      final aisle = _aisles.singleWhere((aisle) => aisle['id'] == id);
      return _json({...aisle, 'hidden': body['hidden']});
    }
    if (path.endsWith('/catalog/products/aisle')) {
      assigned[body['name'] as String] = body['aisleId'] as String?;
      return _json({'id': 'p1', 'name': body['name']});
    }
    return _json({'code': 'not_found', 'message': path}, 404);
  }

  ResponseBody _json(Object body, [int status = 200]) => .fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
