import 'package:flutter/material.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../member_avatar/view/member_avatar.dart';

class ShareSubjectPicker extends StatelessWidget {
  const ShareSubjectPicker({
    super.key,
    required this.members,
    required this.groups,
  });

  final List<Member> members;
  final List<Group> groups;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        // Groups first: whoever joins later is included automatically — that is the point
        // of a group.
        for (final group in groups)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: HiwiskiMetrics.avatarMedium,
              backgroundColor: scheme.secondaryContainer,
              child: Icon(
                HiwiskiSymbols.group,
                color: scheme.onSecondaryContainer,
                size: HiwiskiMetrics.icon20,
              ),
            ),
            title: Text(group.name),
            onTap: () => Navigator.of(context).pop(
              WriteShare(
                subjectType: .group,
                subjectId: group.id,
                level: .read,
              ),
            ),
          ),
        for (final member in members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: MemberAvatar.of(member),
            title: Text(member.displayName),
            onTap: () => Navigator.of(context).pop(
              WriteShare(
                subjectType: .member,
                subjectId: member.id,
                level: .read,
              ),
            ),
          ),
      ],
    );
  }
}
