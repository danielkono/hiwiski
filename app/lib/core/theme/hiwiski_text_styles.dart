import 'package:flutter/widgets.dart';

/// Text styles that fit no Material role.
///
/// Everything Material widgets use on their own lives in the `TextTheme`, not
/// here.
@immutable
class HiwiskiTextStyles {
  const HiwiskiTextStyles({
    required this.sectionLabel,
    required this.prose,
    required this.shoppingLine,
    required this.shoppingAmount,
    required this.entityKey,
    required this.monoSmall,
    required this.inviteCode,
    required this.cardTitle,
    required this.accountName,
  });

  /// "Ingredients", "Sharing", "My calendars" -- 14/w600 in `primary`.
  final TextStyle sectionLabel;

  /// Wiki body text. In Flutter `height` is a **factor** of the font size, like a
  /// unitless `line-height` in CSS: so 1.6 means the same thing.
  final TextStyle prose;

  /// A shopping list row: "**2 l** milk".
  final TextStyle shoppingLine;

  /// The quantity in it, bold.
  final TextStyle shoppingAmount;

  /// `TD-14` -- mono, because it says: you can copy this down.
  final TextStyle entityKey;

  /// Addresses in mono.
  final TextStyle monoSmall;

  /// The invitation code, large and letter-spaced.
  final TextStyle inviteCode;

  /// The title of a list card in the task overview -- 17/w600.
  final TextStyle cardTitle;

  /// The name on the account card -- 18/w600.
  final TextStyle accountName;

  HiwiskiTextStyles lerp(HiwiskiTextStyles other, double t) => .new(
    sectionLabel:
        TextStyle.lerp(sectionLabel, other.sectionLabel, t) ?? sectionLabel,
    prose: TextStyle.lerp(prose, other.prose, t) ?? prose,
    shoppingLine:
        TextStyle.lerp(shoppingLine, other.shoppingLine, t) ?? shoppingLine,
    shoppingAmount:
        TextStyle.lerp(shoppingAmount, other.shoppingAmount, t) ??
        shoppingAmount,
    entityKey: TextStyle.lerp(entityKey, other.entityKey, t) ?? entityKey,
    monoSmall: TextStyle.lerp(monoSmall, other.monoSmall, t) ?? monoSmall,
    inviteCode: TextStyle.lerp(inviteCode, other.inviteCode, t) ?? inviteCode,
    cardTitle: TextStyle.lerp(cardTitle, other.cardTitle, t) ?? cardTitle,
    accountName:
        TextStyle.lerp(accountName, other.accountName, t) ?? accountName,
  );
}
