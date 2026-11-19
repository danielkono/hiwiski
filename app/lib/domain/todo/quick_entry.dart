import '../common/match_groups.dart';

/// What quick entry makes of a line.
///
/// "The shopping list understands '2l milch' — amount, unit, product. **Anything
/// uncertain lands as plain text** and can be split up later."
///
/// The last sentence is the important one: better a line as text than a wrongly
/// split one. "2 Brötchen" is not an amount in pieces but a product with a number
/// in front — and only someone who knows the unit can tell.
class QuickEntry {
  static final _amount = RegExp(
    r'^(\d+(?:[.,]\d+)?)\s*([a-zA-ZäöüÄÖÜ]+)\s+(.+)$',
  );

  const QuickEntry({required this.title, this.amount, this.unit});

  final String title;
  final double? amount;
  final String? unit;

  bool get isStructured => amount != null && unit != null;

  /// The units that are recognised.
  ///
  /// They live in the code, not in the database (catalog).
  /// Conversion only happens exactly within one dimension; "1 Bund" and "200 g"
  /// of parsley make two rows, and that is how it should be.
  static const units = <String, String>{
    'g': 'g',
    'gr': 'g',
    'kg': 'kg',
    'ml': 'ml',
    'l': 'l',
    'liter': 'l',
    'el': 'EL',
    'tl': 'TL',
    'stk': 'Stk',
    'pck': 'Pck',
    'dose': 'Dose',
    'dosen': 'Dose',
    'bund': 'Bund',
    'packung': 'Pck',
  };

  /// `2l milch`, `500 g Mehl`, `1,5 kg Kartoffeln` — and everything else as text.
  static QuickEntry parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return const QuickEntry(title: '');

    // Number, optional comma or dot, optional space, unit, space,
    // rest. The unit is required: without it "2 Brötchen" is a product with
    // a number in front, not an amount.
    final match = _amount.firstMatch(text);

    if (match == null) return QuickEntry(title: text);

    final unit = units[match.groupOf(2).toLowerCase()];
    if (unit == null) return QuickEntry(title: text);

    final amount = double.tryParse(match.groupOf(1).replaceAll(',', '.'));
    if (amount == null) return QuickEntry(title: text);

    return QuickEntry(
      title: match.groupOf(3).trim(),
      amount: amount,
      unit: unit,
    );
  }

  /// "**2 l** Milch" — the amount in bold, in front (`shoppingLine`).
  String get amountLabel {
    final amount = this.amount;
    if (amount == null) return '';
    final value = amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toString().replaceAll('.', ',');
    return unit == null ? value : '$value $unit';
  }
}
