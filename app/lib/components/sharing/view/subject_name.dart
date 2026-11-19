import '../../../core/api/generated/export.dart';

/// The name of a share subject — a group's name or a member's display name, `—`
/// when the subject is not (or no longer) known.
String subjectName(
  ShareSubjectType type,
  String id,
  List<Member> members,
  List<Group> groups,
) => type == .group
    ? groups.where((group) => group.id == id).firstOrNull?.name ?? _unknown
    : members.where((member) => member.id == id).firstOrNull?.displayName ??
          _unknown;

const _unknown = '—';
