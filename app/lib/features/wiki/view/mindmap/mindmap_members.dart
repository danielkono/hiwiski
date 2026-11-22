import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/api/generated/export.dart';

/// The family's members, by id, for the member elements of the map below: whom each
/// shows. Given once around the map rather than to every element.
class MindmapMembers extends InheritedWidget {
  const MindmapMembers({
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
            .dependOnInheritedWidgetOfExactType<MindmapMembers>()
            ?.members[id];

  @override
  bool updateShouldNotify(MindmapMembers oldWidget) =>
      !mapEquals(oldWidget.members, members);
}
