import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/info_line.dart';
import '../../../core/ui/info_section.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/common/uuid_time.dart';
import '../history_view_model.dart';
import 'history_section.dart';

/// The **Info** section of the info bar: Created, Last edited.
///
/// "Created" comes from the **id**: a UUIDv7 carries its timestamp in the first six
/// bytes, so the value is there even offline. "Last edited" comes from the history and
/// stays empty as long as that is not loaded — a guess written down would be worse than
/// a missing row.
class ItemFactsSection extends ConsumerWidget {
  const ItemFactsSection({super.key, required this.item});

  final ItemRef item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(historyViewModelProvider(item))
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (state) => _FactsBody(item: item, state: state),
      );
}

class _FactsBody extends StatelessWidget {
  const _FactsBody({required this.item, required this.state});

  final ItemRef item;
  final HistoryState state;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final history = state.history;
    final members = state.members;
    // Who created it: the creation entry in the history, as long as the log reaches back
    // that far, otherwise the owner from the share sheet — usually the same person.
    final entries = history?.entries ?? const <HistoryEntry>[];
    final creation =
        entries.isEmpty ||
            !isCreationEntry(entries.last, entries, history?.reachesBack, item)
        ? null
        : entries.last;
    // From the id where it is a UUIDv7 (then offline too), otherwise from the
    // creation entry in the history.
    final created = timeOfUuidV7(item.id) ?? creation?.at;
    // Last edited is the newest row — but not the creation itself.
    final edited = entries.isEmpty || entries.first == creation
        ? null
        : entries.first;

    String name(String? id) =>
        members.where((member) => member.id == id).firstOrNull?.displayName ??
        l.historySomeone;
    String stamp(DateTime value) => relativeStamp(l, locale, value);

    final creatorId = creation?.actorId ?? state.ownerId;

    return InfoSection(
      label: l.infoSection,
      children: [
        if (created != null)
          InfoLine(
            label: l.infoCreated,
            value: creatorId == null
                ? stamp(created)
                : l.infoCreatedBy(name(creatorId), stamp(created)),
          ),
        if (edited != null)
          InfoLine(
            label: l.infoUpdated,
            value: '${name(edited.actorId)}, ${stamp(edited.at)}',
          ),
      ],
    );
  }
}

/// "today 07:12", "yesterday 18:30", otherwise "21.09.2026" — as in the design.
String relativeStamp(L l, String locale, DateTime value) {
  final local = value.toLocal();
  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final time = DateFormat.Hm(locale).format(local);
  if (day == today) return l.stampToday(time);
  // The day before on the calendar, not 24 hours before midnight: after a clock
  // change that was 23:00 two days back, or 01:00 yesterday — never "yesterday".
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return l.stampYesterday(time);
  }
  return DateFormat.yMd(locale).format(local);
}
