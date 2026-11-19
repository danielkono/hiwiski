import 'package:flutter/widgets.dart';

import '../api/generated/export.dart';
import '../theme/hiwiski_symbols.dart';
import '../l10n/generated/app_localizations.dart';

/// The icons a group can choose from — as the name of the Material symbol, just as
/// `iconToken` appears in the contract.
const groupIconTokens = <String, IconData>{
  _familyToken: HiwiskiSymbols.familyRestroom,
  _parentsToken: HiwiskiSymbols.supervisorAccount,
  _childrenToken: HiwiskiSymbols.childCare,
  _elderToken: HiwiskiSymbols.elderly,
  _tabletToken: HiwiskiSymbols.tablet,
  _groupToken: HiwiskiSymbols.group,
};

/// What a group symbol shows — for its tooltip and a screen reader.
String groupIconLabel(L l, String token) => switch (token) {
  _familyToken => l.groupIconFamily,
  _parentsToken => l.groupIconParents,
  _childrenToken => l.groupIconChildren,
  _elderToken => l.groupIconElders,
  _tabletToken => l.groupIconTablet,
  _ => l.groupIconGroup,
};

const _familyToken = 'family_restroom';
const _parentsToken = 'supervisor_account';
const _childrenToken = 'child_care';
const _elderToken = 'elderly';
const _tabletToken = 'tablet';
const _groupToken = 'group';

// What a group's name gives away, in the app's two languages.
const _parentHints = ['eltern', 'parent'];
const _childHints = ['kind', 'child', 'kid'];
const _everyoneHints = ['everyone', 'alle', 'famil'];
const _everyoneExact = 'all';
const _tabletHint = 'tablet';
const _elderHints = ['groß', 'oma', 'grand'];

/// The obvious icon for a group's name — "Parents", "Children", "Everyone" from the
/// setup wizard carry none.
///
/// Grandparents first: "Großeltern" and "Grandparents" both contain a parent hint,
/// and checked after it, the elderly icon was never reached.
String guessedIconToken(String groupName) {
  final name = groupName.toLowerCase();
  if (_elderHints.any(name.contains)) return _elderToken;
  if (_parentHints.any(name.contains)) return _parentsToken;
  if (_childHints.any(name.contains)) return _childrenToken;
  if (_everyoneHints.any(name.contains) || name == _everyoneExact) {
    return _familyToken;
  }
  if (name.contains(_tabletHint)) return _tabletToken;
  return _groupToken;
}

/// The icon of a group: the one chosen — `group` too, when it was picked — or else
/// the obvious one for its name.
IconData groupIcon(Group group) =>
    groupIconTokens[group.iconToken ?? guessedIconToken(group.name)] ??
    HiwiskiSymbols.group;
