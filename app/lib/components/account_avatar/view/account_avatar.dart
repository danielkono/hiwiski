import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../member_avatar/view/member_avatar.dart';
import '../account_avatar_view_model.dart';

/// The avatar circle with the initial that leads to the account.
class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({super.key, required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(accountAvatarViewModelProvider);
    if (member == null) return const SizedBox.shrink();
    return Padding(
      padding: const .only(left: HiwiskiMetrics.space4),
      child: Tooltip(
        message: L.of(context).accountTitle,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => const AccountRoute().go(context),
          // The circle keeps its size; around it, the area a finger reliably hits.
          // The initial is not read out: the tooltip says where the tap leads.
          child: SizedBox.square(
            dimension: math.max(HiwiskiMetrics.minTapTarget, 2 * radius),
            child: Center(
              child: ExcludeSemantics(
                child: MemberAvatar.of(member, radius: radius),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
