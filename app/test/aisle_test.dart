import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations_de.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations_en.dart';
import 'package:hiwiski/domain/catalog/catalog_product.dart';
import 'package:hiwiski/features/todo/view/aisle_ui.dart';

/// **The shopping list's categories belong to the family**: built-in
/// ones are keys shown in the app's language, own ones are shown as written, and the
/// order is the family's.
void main() {
  final en = LEn();
  final de = LDe();

  CatalogAisle builtIn(String key, int position, {bool hidden = false}) =>
      .new(id: key, key: key, position: position, hidden: hidden);

  CatalogProduct product(String name, String? aisleId) =>
      .new(id: name, name: name, aisleId: aisleId, usageCount: 0);

  group('labels', () {
    test('every built-in category has a translation of its own', () {
      final labels = {
        for (final key in AisleKeys.all) aisleLabel(en, builtIn(key, 0)),
      };
      expect(labels, hasLength(AisleKeys.all.length));
      expect(labels, isNot(contains('Other')));
      expect(
        aisleLabel(en, builtIn(AisleKeys.produce, 0)),
        equals('Fruit & vegetables'),
      );
      expect(
        aisleLabel(de, builtIn(AisleKeys.produce, 0)),
        equals('Obst & Gemüse'),
      );
    });

    test('an own category is shown as written, in every language', () {
      const own = CatalogAisle(id: 'a', name: 'Asia-Laden', position: 15);
      expect(aisleLabel(en, own), equals('Asia-Laden'));
      expect(aisleLabel(de, own), equals('Asia-Laden'));
    });

    test('none, and a key this app does not know, is "Other"', () {
      expect(aisleLabel(en, null), equals('Other'));
      expect(aisleLabel(en, builtIn('hardware', 0)), equals('Other'));
    });
  });

  group('aisleFor', () {
    final products = [
      product('Kürbis', 'produce'),
      product('Hokkaido-Kürbis', 'frozen'),
      product('Milch', 'dairy_eggs'),
      product('Hafermilch', 'beverages'),
    ];

    test('an exact name wins over a contained one', () {
      expect(aisleFor('hokkaido-kürbis', null, products), equals('frozen'));
      expect(aisleFor('Kürbis', null, products), equals('produce'));
    });

    test('otherwise the longest contained name', () {
      expect(aisleFor('Bio-Hafermilch', null, products), equals('beverages'));
      expect(aisleFor('Frische Milch', null, products), equals('dairy_eggs'));
      expect(aisleFor('Sojasoße', null, products), isNull);
    });
  });

  // A row linked to "Kürbis" but titled "Hokkaido-Kürbis": a move written under the
  // title went to another product, and the row jumped back.
  test('a category change goes under the linked product', () {
    final pumpkin = product('Kürbis', 'produce');
    expect(
      catalogNameFor('Hokkaido-Kürbis', pumpkin.id, [pumpkin]),
      equals('Kürbis'),
    );
    expect(catalogNameFor('Hafermilch', null, [pumpkin]), equals('Hafermilch'));
  });

  group('groupByAisle', () {
    List<(String?, String)> grouped(
      List<String> rows,
      List<CatalogProduct> products,
      List<CatalogAisle> aisles,
    ) => [
      for (final (aisle, titles) in groupByAisle(
        rows,
        title: (row) => row,
        productId: (_) => null,
        products: products,
        aisles: aisles,
      ))
        (aisle?.id, titles.join(', ')),
    ];

    test('in the family\'s order, "Other" last', () {
      final aisles = [
        builtIn(AisleKeys.frozen, 0),
        builtIn(AisleKeys.produce, 1),
        const CatalogAisle(id: 'asia', name: 'Asia shop', position: 2),
      ];
      final products = [
        product('Äpfel', 'produce'),
        product('Eis', 'frozen'),
        product('Sojasoße', 'asia'),
      ];
      expect(
        grouped(['Sojasoße', 'Nägel', 'Äpfel', 'Eis'], products, aisles),
        equals([
          ('frozen', 'Eis'),
          ('produce', 'Äpfel'),
          ('asia', 'Sojasoße'),
          (null, 'Nägel'),
        ]),
      );
    });

    test('a hidden or unknown category goes under "Other"', () {
      final aisles = [
        builtIn(AisleKeys.baby, 0, hidden: true),
        builtIn('hardware', 1),
      ];
      final products = [
        product('Windeln', 'baby'),
        product('Nägel', 'hardware'),
      ];
      expect(
        grouped(['Windeln', 'Nägel'], products, aisles),
        equals([(null, 'Windeln, Nägel')]),
      );
    });
  });
}
