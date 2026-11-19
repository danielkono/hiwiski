import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../domain/common/item_ref.dart';
import '../sharing_view_model.dart';
import 'subject_name.dart';

/// The share in half a sentence: "Everyone sees · Parents edit", "Only you",
/// laid out by [builder]. Nothing while nothing is
/// loaded.
class ShareSummaryBuilder extends ConsumerWidget {
  const ShareSummaryBuilder({
    super.key,
    required this.item,
    required this.builder,
  });

  final ItemRef item;
  final Widget Function(BuildContext context, IconData icon, String text)
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(sharingAvailableViewModelProvider)) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(sharingViewModelProvider(item)).value;
    final summary = state == null ? null : _summary(L.of(context), state);
    if (summary == null) return const SizedBox.shrink();
    return builder(context, summary.$1, summary.$2);
  }
}

/// The summary line: an icon and who may do what.
(IconData, String)? _summary(L l, SharingState state) {
  final sheet = state.sheet;
  final members = state.directory.members;
  final groups = state.directory.groups;

  final others = sheet.entries
      .where((entry) => entry.source == .direct || entry.source == .inherited)
      .toList();
  if (others.isEmpty) return (HiwiskiSymbols.lock, l.shareOnlyYou);

  String name(ShareEntry entry) =>
      subjectName(entry.subjectType, entry.subjectId, members, groups);
  String verb(AccessLevel level) => switch (level) {
    .write => l.shareVerbWrite,
    .check => l.shareVerbCheck,
    _ => l.shareVerbRead,
  };

  return (
    HiwiskiSymbols.familyRestroom,
    others.map((entry) => '${name(entry)} ${verb(entry.level)}').join(' · '),
  );
}
