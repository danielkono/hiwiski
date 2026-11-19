import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';

import '../../core/api/generated/models/aisle.dart';
import '../../core/api/generated/models/aisle_order_request.dart';
import '../../core/api/generated/models/assign_product_aisle_request.dart';
import '../../core/api/generated/models/create_aisle_request.dart';
import '../../core/api/generated/models/product.dart';
import '../../core/api/generated/models/update_aisle_request.dart';
import '../../core/api/hiwiski_api.dart';
import '../../core/api/hiwiski_failure.dart';
import '../../core/common/ids.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/storage/local_settings.dart';
import '../../domain/catalog/catalog_product.dart';
import '../../domain/catalog/catalog_seed.dart';

/// The product catalogue and the shopping list's categories on the device.
///
/// Both belong to everyone and have no share; that is why they come over REST and not
/// over the sync. They live here so that the shopping
/// list knows which category "Quark" belongs in, even offline.
///
/// **Changes need a connection** (F): each write goes to the
/// server first and lands in the mirror with the server's answer. Offline it fails
/// with a network [HiwiskiFailure], and the mirror stays as it was.
///
/// **Without a server** the device is the family: the catalogue starts
/// from the seed the server would have started from, and each write follows the
/// server's rules here. When the device connects, [carryOver] brings its own
/// categories and assignments to the server before the server's catalogue replaces
/// the device's.
class CatalogRepository {
  CatalogRepository({
    required this._db,
    required this._api,
    required this._settings,
    required this._serverless,
    required this._seed,
  });

  final HiwiskiDatabase _db;
  final HiwiskiApi _api;
  final LocalSettings _settings;
  final bool _serverless;

  /// The seed in the app's language, as the server keeps it.
  final Future<String> Function() _seed;

  /// The carry-over under way, if any — one at a time.
  Future<void>? _carrying;

  /// Fetches the catalogue again. If that fails — offline — the old one stays.
  ///
  /// Without a server there is nothing to fetch: a catalogue that is still empty
  /// gets the seed.
  Future<void> refresh() async {
    if (_serverless) {
      await _seedIfEmpty();
      return;
    }
    try {
      // What was made without a server goes first: replaced by the server's
      // catalogue, it would be gone.
      if (_settings.catalogCarryover) await carryOver();
      final aisles = await HiwiskiApi.run(() => _api.catalog.listAisles());
      final list = await HiwiskiApi.run(() => _api.catalog.listProducts());
      // Replaced as a whole: a category deleted on another device has to go here too.
      await _db.transaction(() async {
        await _db.delete(_db.aisles).go();
        await _db.delete(_db.products).go();
        await _db.batch((batch) {
          batch.insertAll(_db.aisles, [
            for (final aisle in aisles.aisles) aisle.toCompanion(),
          ]);
          batch.insertAll(_db.products, [
            for (final product in list.products) product.toCompanion(),
          ]);
        });
      });
    } on Object catch (error) {
      // Offline or an old server: the last fetched catalogue is good enough.
      debugPrint('hiwiski: catalogue not refreshed: $error');
    }
  }

  bool _fetched = false;

  /// The catalogue and its categories are fetched fresh from the server once, when
  /// either is first watched. The repository lives as long as the session: once per
  /// session.
  void _fetchOnce() {
    if (_fetched) return;
    _fetched = true;
    // Offline the last fetched catalogue stays; refresh logs why.
    refresh().ignore();
  }

  Stream<List<CatalogProduct>> watch() {
    _fetchOnce();
    return _watchProducts();
  }

  Stream<List<CatalogProduct>> _watchProducts() => _db
      .select(_db.products)
      .watch()
      .map((rows) => [for (final row in rows) row.toDomain()]);

  /// All categories in their order, hidden ones included.
  Stream<List<CatalogAisle>> watchAisles() {
    _fetchOnce();
    return _watchAisles();
  }

  Stream<List<CatalogAisle>> _watchAisles() =>
      (_db.select(_db.aisles)
            ..orderBy([(aisle) => OrderingTerm.asc(aisle.position)]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);

  /// The product with exactly this name goes into this category — created if there is
  /// none. `null` takes the category away.
  Future<void> assignAisle(String productName, String? aisleId) async {
    if (_serverless) return _assignHere(productName, aisleId);
    final product = await HiwiskiApi.run(
      () => _api.catalog.assignProductAisle(
        body: AssignProductAisleRequest(name: productName, aisleId: aisleId),
      ),
    );
    await _db.into(_db.products).insertOnConflictUpdate(product.toCompanion());
  }

  /// One of the family's own, at the end of the order.
  Future<CatalogAisle> createAisle(String name) async {
    if (_serverless) return _createHere(name);
    final aisle = await HiwiskiApi.run(
      () => _api.catalog.createAisle(body: CreateAisleRequest(name: name)),
    );
    await _db.into(_db.aisles).insertOnConflictUpdate(aisle.toCompanion());
    return aisle.toDomain();
  }

  Future<void> renameAisle(String id, String name) =>
      _update(id, UpdateAisleRequest(name: name));

  Future<void> setAisleHidden(String id, bool hidden) =>
      _update(id, UpdateAisleRequest(hidden: hidden));

  Future<void> _update(String id, UpdateAisleRequest body) async {
    if (_serverless) {
      return _updateHere(id, name: body.name, hidden: body.hidden);
    }
    final aisle = await HiwiskiApi.run(
      () => _api.catalog.updateAisle(id: id, body: body),
    );
    await _db.into(_db.aisles).insertOnConflictUpdate(aisle.toCompanion());
  }

  /// Its products lose their category, as on the server.
  Future<void> deleteAisle(String id) async {
    if (_serverless) {
      if ((await _aisle(id)).key != null) {
        throw const HiwiskiFailure(code: FailureCodes.catalogAisleBuiltin);
      }
    } else {
      await HiwiskiApi.run(() => _api.catalog.deleteAisle(id: id));
    }
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((p) => p.aisleId.equals(id)))
          .write(const ProductsCompanion(aisleId: Value(null)));
      await (_db.delete(_db.aisles)..where((a) => a.id.equals(id))).go();
    });
  }

  Future<void> reorderAisles(List<String> ids) async {
    if (_serverless) return _reorderHere(ids);
    final list = await HiwiskiApi.run(
      () => _api.catalog.reorderAisles(body: AisleOrderRequest(ids: ids)),
    );
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.aisles, [
        for (final aisle in list.aisles) aisle.toCompanion(),
      ]);
    });
  }

  // --- Without a server ---------------------------------------------

  /// The built-in categories in their order and the seed's products — once, into an
  /// empty catalogue. One already there (the device was on a server before) stays.
  Future<void> _seedIfEmpty() async {
    final known =
        await (_db.selectOnly(_db.aisles)..addColumns([_db.aisles.id.count()]))
            .map((row) => row.read(_db.aisles.id.count()) ?? 0)
            .getSingle();
    if (known > 0) return;
    final products = parseCatalogSeed(await _seed());
    final aisleIds = {for (final key in AisleKeys.all) key: newId()};
    await _db.transaction(() async {
      // The same check once more inside: two screens open at the start both found
      // the catalogue empty.
      if (await _db.select(_db.aisles).get() case [_, ...]) return;
      await _db.batch((batch) {
        batch.insertAll(_db.aisles, [
          for (final (position, key) in AisleKeys.all.indexed)
            AislesCompanion.insert(
              id: aisleIds[key]!,
              key: Value(key),
              position: position,
            ),
        ]);
        batch.insertAll(_db.products, [
          for (final product in products)
            ProductsCompanion.insert(
              id: newId(),
              name: product.name,
              aisleId: Value(aisleIds[product.aisleKey]),
              defaultUnit: Value(product.defaultUnit),
            ),
        ]);
      });
    });
  }

  Future<AisleRow> _aisle(String id) async =>
      await (_db.select(
        _db.aisles,
      )..where((aisle) => aisle.id.equals(id))).getSingleOrNull() ??
      (throw const HiwiskiFailure(code: FailureCodes.catalogAisleNotFound));

  /// The server's rule: one product per name, whatever its case.
  Future<void> _assignHere(String productName, String? aisleId) async {
    final name = productName.trim();
    if (name.isEmpty) {
      throw const HiwiskiFailure(code: FailureCodes.catalogProductNameRequired);
    }
    if (aisleId != null) await _aisle(aisleId);
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.products)..where(
                (product) => product.name.lower().equals(name.toLowerCase()),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_db.products)
            .insert(
              ProductsCompanion.insert(
                id: newId(),
                name: name,
                aisleId: Value(aisleId),
                assignedHere: const Value(true),
              ),
            );
        return;
      }
      await (_db.update(
        _db.products,
      )..where((product) => product.id.equals(existing.id))).write(
        ProductsCompanion(
          aisleId: Value(aisleId),
          assignedHere: const Value(true),
        ),
      );
    });
  }

  /// The server's rule: a name, not taken by another category.
  Future<void> _requireNameFree(String name, {String? except}) async {
    final taken =
        await (_db.select(_db.aisles)..where(
              (aisle) =>
                  aisle.name.lower().equals(name.toLowerCase()) &
                  (except == null
                      ? const Constant(true)
                      : aisle.id.equals(except).not()),
            ))
            .get();
    if (taken.isNotEmpty) {
      throw const HiwiskiFailure(code: FailureCodes.catalogAisleNameTaken);
    }
  }

  static String _requireName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      throw const HiwiskiFailure(code: FailureCodes.catalogAisleNameRequired);
    }
    return trimmed;
  }

  Future<CatalogAisle> _createHere(String name) => _db.transaction(() async {
    final trimmed = _requireName(name);
    await _requireNameFree(trimmed);
    final last =
        await (_db.selectOnly(_db.aisles)
              ..addColumns([_db.aisles.position.max()]))
            .map((row) => row.read(_db.aisles.position.max()))
            .getSingle();
    final row = AisleRow(
      id: newId(),
      name: trimmed,
      position: last == null ? 0 : last + 1,
      hidden: false,
    );
    await _db.into(_db.aisles).insert(row);
    return row.toDomain();
  });

  Future<void> _updateHere(String id, {String? name, bool? hidden}) =>
      _db.transaction(() async {
        final row = await _aisle(id);
        AisleRow changed = row;
        if (name != null) {
          if (row.key != null) {
            throw const HiwiskiFailure(code: FailureCodes.catalogAisleBuiltin);
          }
          final trimmed = _requireName(name);
          await _requireNameFree(trimmed, except: id);
          changed = changed.copyWith(name: Value(trimmed));
        }
        if (hidden != null) changed = changed.copyWith(hidden: hidden);
        await _db.update(_db.aisles).replace(changed);
      });

  /// The server's rule: the named ones first, in the given order, the rest after
  /// them as they were.
  Future<void> _reorderHere(List<String> ids) => _db.transaction(() async {
    final rows = await (_db.select(
      _db.aisles,
    )..orderBy([(aisle) => OrderingTerm.asc(aisle.position)])).get();
    final byId = {for (final row in rows) row.id: row};
    final order = <String>{
      for (final id in ids)
        if (byId.containsKey(id)) id,
      for (final row in rows) row.id,
    };
    for (final (position, id) in order.indexed) {
      if (byId[id]!.position == position) continue;
      await (_db.update(_db.aisles)..where((aisle) => aisle.id.equals(id)))
          .write(AislesCompanion(position: Value(position)));
    }
  });

  /// Brings what the device made without a server to the server it connected to:
  /// its own categories (by name, if the family has one of that name already),
  /// what it hid and how it ordered them, and the products it put into a category.
  /// The server's catalogue then replaces the device's.
  ///
  /// Once: the mark is cleared when it is through. A failure leaves it for the next
  /// try, and every step can be repeated — a category found by its name is not made
  /// twice, an assignment written twice is the same.
  Future<void> carryOver() => _carrying ??= _carryOver().whenComplete(() {
    _carrying = null;
  });

  Future<void> _carryOver() async {
    if (_serverless || !_settings.catalogCarryover) return;
    final local = await (_db.select(
      _db.aisles,
    )..orderBy([(aisle) => OrderingTerm.asc(aisle.position)])).get();
    final assigned = await (_db.select(
      _db.products,
    )..where((product) => product.assignedHere.equals(true))).get();
    final remote = (await HiwiskiApi.run(() => _api.catalog.listAisles()))
        .aisles;

    final onServer = <String, Aisle>{};
    for (final aisle in local) {
      final match = remote
          .where(
            (candidate) => aisle.key != null
                ? candidate.key == aisle.key
                : candidate.name?.toLowerCase() == aisle.name?.toLowerCase(),
          )
          .firstOrNull;
      final name = aisle.name;
      final target =
          match ??
          (aisle.key == null && name != null
              ? await HiwiskiApi.run(
                  () => _api.catalog.createAisle(
                    body: CreateAisleRequest(name: name),
                  ),
                )
              : null);
      if (target == null) continue;
      onServer[aisle.id] = target;
      if (target.hidden != aisle.hidden) {
        await HiwiskiApi.run(
          () => _api.catalog.updateAisle(
            id: target.id,
            body: UpdateAisleRequest(hidden: aisle.hidden),
          ),
        );
      }
    }
    await HiwiskiApi.run(
      () => _api.catalog.reorderAisles(
        body: AisleOrderRequest(
          ids: [
            for (final aisle in local)
              if (onServer[aisle.id] case final target?) target.id,
          ],
        ),
      ),
    );
    for (final product in assigned) {
      await HiwiskiApi.run(
        () => _api.catalog.assignProductAisle(
          body: AssignProductAisleRequest(
            name: product.name,
            aisleId: switch (product.aisleId) {
              null => null,
              final id => onServer[id]?.id,
            },
          ),
        ),
      );
    }
    await _settings.setCatalogCarryover(false);
  }
}

extension on Product {
  ProductsCompanion toCompanion() => .insert(
    id: id,
    name: name,
    aisleId: Value(aisleId),
    defaultUnit: Value(defaultUnit),
    usageCount: Value(usageCount ?? 0),
  );
}

extension on Aisle {
  AislesCompanion toCompanion() => .insert(
    id: id,
    key: Value(key),
    name: Value(name),
    position: position,
    hidden: Value(hidden),
  );

  CatalogAisle toDomain() =>
      .new(id: id, key: key, name: name, position: position, hidden: hidden);
}

extension on ProductRow {
  CatalogProduct toDomain() => .new(
    id: id,
    name: name,
    aisleId: aisleId,
    defaultUnit: defaultUnit,
    usageCount: usageCount,
  );
}

extension on AisleRow {
  CatalogAisle toDomain() =>
      .new(id: id, key: key, name: name, position: position, hidden: hidden);
}
