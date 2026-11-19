import '../../../core/api/generated/export.dart';

/// The names of the [groups] that [ids] name, in the groups' order — for a member's or
/// an invitation's groups. Written out three times before.
List<String> groupNamesOf(List<Group> groups, Iterable<String> ids) {
  final wanted = ids.toSet();
  return [
    for (final group in groups)
      if (wanted.contains(group.id)) group.name,
  ];
}
