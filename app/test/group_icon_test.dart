import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/theme/hiwiski_symbols.dart';
import 'package:hiwiski/core/ui/group_icon.dart';

/// The icon a group shows: the one picked, or the obvious one for its name.
void main() {
  Group group(String name, {String? icon}) => .new(
    id: 'g',
    name: name,
    position: 0,
    memberIds: const [],
    iconToken: icon,
  );

  // "Großeltern" contains "eltern" and got the parents icon.
  test('grandparents are not parents', () {
    expect(groupIcon(group('Großeltern')), equals(HiwiskiSymbols.elderly));
    expect(groupIcon(group('Grandparents')), equals(HiwiskiSymbols.elderly));
    expect(
      groupIcon(group('Eltern')),
      equals(HiwiskiSymbols.supervisorAccount),
    );
  });

  // A picked "group" icon was taken for "not chosen".
  test('a picked icon wins over the name', () {
    expect(
      groupIcon(group('Eltern', icon: 'group')),
      equals(HiwiskiSymbols.group),
    );
  });
}
