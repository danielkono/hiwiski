import '../common/wire.dart';
import '../theme/hiwiski_accents.dart';
import '../l10n/generated/app_localizations.dart';

/// From the stored color token to the accent.
///
/// What is stored is **a token, not a hex value**: a stored hex
/// value would be unreadable in one of the two themes.
AccentToken accentOf(String token) => switch (token) {
  ColorTokens.rust => AccentToken.rust,
  ColorTokens.violet => AccentToken.violet,
  ColorTokens.green => AccentToken.green,
  ColorTokens.pink => AccentToken.pink,
  ColorTokens.ochre => AccentToken.ochre,
  ColorTokens.teal => AccentToken.teal,
  ColorTokens.slate => AccentToken.slate,
  _ => AccentToken.blue,
};

/// The eight dots from the design, in the order of the color picker.
/// What a color is called — for the dots that pick one, which show nothing else.
String colorLabel(L l, String token) => switch (token) {
  ColorTokens.blue => l.colorBlue,
  ColorTokens.rust => l.colorRust,
  ColorTokens.violet => l.colorViolet,
  ColorTokens.green => l.colorGreen,
  ColorTokens.pink => l.colorPink,
  ColorTokens.ochre => l.colorOchre,
  ColorTokens.teal => l.colorTeal,
  ColorTokens.slate => l.colorSlate,
  ColorTokens.red => l.colorRed,
  ColorTokens.amber => l.colorAmber,
  _ => token,
};

const calendarColorTokens = <String>[
  'BLUE',
  'RUST',
  'VIOLET',
  'GREEN',
  'PINK',
  'OCHRE',
  'TEAL',
  'SLATE',
];

/// The light background for a calendar — for the pinned strip, which the design shows
/// as a tinted pill ("Summer holidays 29.09.–10.10." on pink).
TagToken tintOf(String token) => switch (accentOf(token)) {
  .rust => TagToken.red,
  .violet => TagToken.violet,
  .green || .teal => TagToken.green,
  .pink => TagToken.pink,
  .ochre => TagToken.amber,
  _ => TagToken.blue,
};
