import 'package:hiwiski/domain/todo/quick_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// "The shopping list understands '2l milch'. Anything uncertain ends up as plain text."
void main() {
  test('recognizes amount, unit and product', () {
    final entry = QuickEntry.parse('2l milch');
    expect(entry.amount, equals(2));
    expect(entry.unit, equals('l'));
    expect(entry.title, equals('milch'));
    expect(entry.amountLabel, equals('2 l'));
  });

  test('recognizes a space and a decimal comma', () {
    final entry = QuickEntry.parse('1,5 kg Kartoffeln');
    expect(entry.amount, equals(1.5));
    expect(entry.unit, equals('kg'));
    expect(entry.title, equals('Kartoffeln'));
    expect(entry.amountLabel, equals('1,5 kg'));
  });

  test('a number without a unit is not an amount', () {
    // "2 Brötchen" is a product with a number in front. Better a line as text than one
    // that was split wrongly.
    final entry = QuickEntry.parse('2 Brötchen');
    expect(entry.isStructured, isFalse);
    expect(entry.title, equals('2 Brötchen'));
  });

  test('ordinary text stays text', () {
    final entry = QuickEntry.parse('Fenster putzen');
    expect(entry.isStructured, isFalse);
    expect(entry.title, equals('Fenster putzen'));
  });

  test('a bunch stays a bunch', () {
    // "1 Bund" and "200 g" of parsley make two lines -- conversion only happens exactly
    // within one dimension (catalog).
    final bunch = QuickEntry.parse('1 Bund Petersilie');
    final grams = QuickEntry.parse('200 g Petersilie');
    expect(bunch.unit, equals('Bund'));
    expect(grams.unit, equals('g'));
    expect(bunch.unit, isNot(grams.unit));
  });
}
