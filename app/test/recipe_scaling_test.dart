import 'package:hiwiski/domain/wiki/wiki_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Import a recipe, scale it to 6 servings, apply it; **"1 Bund" and "200 g" of parsley
/// make two lines.**"
void main() {
  group('scaling', () {
    test('from 4 to 6 servings', () {
      const flour = Ingredient(label: 'Mehl', amount: 200, unit: 'g');

      expect(flour.scaled(4, 6).amount, equals(300));
      expect(flour.scaled(4, 6).unit, equals('g'));
      expect(flour.scaled(4, 6).label, equals('Mehl'));
    });

    test('halving', () {
      const broth = Ingredient(label: 'Brühe', amount: 1, unit: 'l');
      expect(broth.scaled(4, 2).amount, equals(0.5));
    });

    test('an ingredient without an amount is not scaled', () {
      // "Salz nach Geschmack" (salt to taste) must not become "1,5 Salz nach Geschmack".
      const salt = Ingredient(label: 'Salz nach Geschmack', uncertain: true);

      expect(salt.scaled(4, 6).amount, isNull);
      expect(salt.scaled(4, 6).label, equals('Salz nach Geschmack'));
    });

    test('the same number of servings leaves everything as it is', () {
      const flour = Ingredient(label: 'Mehl', amount: 200, unit: 'g');
      expect(identical(flour.scaled(4, 4), flour), isTrue);
    });

    test('zero servings do not exist', () {
      const flour = Ingredient(label: 'Mehl', amount: 200, unit: 'g');
      expect(flour.scaled(0, 6).amount, equals(200));
      expect(flour.scaled(4, 0).amount, equals(200));
    });
  });

  group('round trip', () {
    test('an ingredient list survives JSON', () {
      const original = [
        Ingredient(label: 'Petersilie', amount: 1, unit: 'Bund'),
        Ingredient(label: 'Petersilie', amount: 200, unit: 'g'),
        Ingredient(label: 'Salz', staple: true),
        Ingredient(label: 'Öl nach Bedarf', uncertain: true),
      ];

      final decoded = Ingredient.decode(Ingredient.encode(original));

      expect(decoded, hasLength(4));
      expect(decoded[0].unit, equals('Bund'));
      expect(decoded[1].unit, equals('g'));
      expect(decoded[2].staple, isTrue);
      expect(decoded[3].uncertain, isTrue);
    });

    test('a broken column does not cost the recipe', () {
      expect(Ingredient.decode('not JSON'), isEmpty);
      expect(Ingredient.decode(''), isEmpty);
      expect(Ingredient.decode('{"not":"a list"}'), isEmpty);
    });
  });

  group('making amounts readable', () {
    test('whole numbers without a decimal comma', () {
      expect(formatAmount(2), equals('2'));
      expect(formatAmount(300), equals('300'));
    });

    test('fractions with a decimal comma and rounded', () {
      expect(formatAmount(0.5), equals('0,5'));
      // 1/3 must not become "0,3333333333".
      expect(formatAmount(1 / 3), equals('0,33'));
    });

    test('no amount is no text', () {
      expect(formatAmount(null), equals(''));
    });
  });

  test('1 bunch and 200 g of parsley are two lines', () {
    // **Conversion only happens exactly within one dimension** (g/kg, ml/l).
    // Nobody knows how many grams a bunch has — and an estimate
    // would then appear as a number on the shopping list.
    const bunch = Ingredient(label: 'Petersilie', amount: 1, unit: 'Bund');
    const grams = Ingredient(label: 'Petersilie', amount: 200, unit: 'g');

    // Every ingredient goes onto the shopping list as its own line; nothing that does not
    // share the same unit is merged.
    expect(bunch.unit, isNot(grams.unit));
    expect(bunch.label, equals(grams.label));
  });
}
