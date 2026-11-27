import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/api/generated/export.dart';

/// The family's members, by id, for the member elements of the map below: whom each
/// shows. Given once around the map rather than to every element.
class PinboardMembers extends InheritedWidget {
  const PinboardMembers({
    super.key,
    required this.members,
    required super.child,
  });

  final Map<String, Member> members;

  /// The member [id] names — `null` when they are not in the family (any more), or
  /// not known on this device yet.
  static Member? of(BuildContext context, String? id) => id == null
      ? null
      : context
            .dependOnInheritedWidgetOfExactType<PinboardMembers>()
            ?.members[id];

  @override
  bool updateShouldNotify(PinboardMembers oldWidget) =>
      !mapEquals(oldWidget.members, members);
}
