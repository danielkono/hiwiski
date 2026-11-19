import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../components/rich_text/view/rich_markdown.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../domain/calendar/calendar_kinds.dart';
import '../../../../domain/calendar/occurrence.dart';
import '../../view/event_when.dart';
import '../../view/reminder_picker.dart';
import '../event_view_model.dart';

/// What the event's view shows besides comments and info bar: when, the read-only
/// notice, place, reminder, attendees and the note. A link's preview shows it as it is
/// — nothing in it changes the event.
class EventBody extends ConsumerWidget {
  // "Open map": a search on OpenStreetMap, no embedded map service.
  static const _mapHost = 'www.openstreetmap.org';
  static const _mapSearch = '/search';
  static const _mapQuery = 'query';

  const EventBody({super.key, required this.eventId, this.at});

  final String eventId;

  /// The start of the intended occurrence of a series; without it, the one around now.
  final DateTime? at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(eventViewModelProvider(eventId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox.shrink(),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (state) => state == null
              ? const SizedBox.shrink()
              : _EventBody(at: at, state: state),
        );
  }
}

class _EventBody extends ConsumerWidget {
  const _EventBody({required this.at, required this.state});

  final DateTime? at;
  final EventState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final row = state.event;

    final calendar = state.calendar;
    final subscribed = state.subscribed;
    final readOnly = state.readOnly;
    final occurrence = occurrenceNear(row, at: at);
    final color = context.tokens.accent(
      accentOf(calendar?.colorToken ?? ColorTokens.blue),
    );

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _When(occurrence: occurrence, event: row, color: color),
        const SizedBox(height: HiwiskiMetrics.space20),
        if (readOnly) ...[
          NoticeBar.readOnly(
            context,
            reason: switch (calendar?.kind) {
              kindImported => l.calReadOnlyImported,
              _ when subscribed => l.calReadOnlySubscription,
              _ => l.stateReadOnlyShared,
            },
          ),
          const SizedBox(height: HiwiskiMetrics.space16),
        ],
        _Line(
          icon: HiwiskiSymbols.locationOn,
          text: switch (row.location) {
            final location? when location.isNotEmpty => location,
            _ => l.calNoLocation,
          },
          trailing: (row.location ?? '').isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    HiwiskiSymbols.map,
                    size: HiwiskiMetrics.icon20,
                  ),
                  tooltip: l.calOpenMap,
                  onPressed: () => launchUrl(
                    Uri.https(EventBody._mapHost, EventBody._mapSearch, {
                      EventBody._mapQuery: row.location,
                    }),
                  ),
                ),
        ),
        _Line(
          icon: HiwiskiSymbols.notifications,
          text: eventReminderLabel(
            l,
            row.reminderMinutes,
            calendar?.defaultReminderMinutes,
          ),
        ),
        _Line(
          icon: HiwiskiSymbols.assignmentInd,
          text: state.attendees.isEmpty
              ? l.calNoAttendees
              : state.attendees.join(', '),
        ),
        if (row.description case final note? when note.trim().isNotEmpty) ...[
          const SizedBox(height: HiwiskiMetrics.space16),
          Text(l.calNote, style: context.tokens.text.sectionLabel),
          const SizedBox(height: HiwiskiMetrics.space6),
          // Read like a wiki page: chips, images, boxes to tick.
          RichMarkdown(
            text: note,
            onOpen: (target) => openLinkTarget(context, ref, target),
            onToggleTask: readOnly
                ? null
                : (index) => ref
                      .read(eventViewModelProvider(row.id).notifier)
                      .toggleNoteTask(row, index),
          ),
        ],
      ],
    );
  }
}

/// A row with a symbol, 48 high.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.trailing});

  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: HiwiskiMetrics.formRowHeight),
    child: Row(
      children: [
        Icon(
          icon,
          size: HiwiskiMetrics.icon22,
          color: context.scheme.onSurfaceVariant,
        ),
        const SizedBox(width: HiwiskiMetrics.space14),
        Expanded(child: Text(text, style: context.texts.bodyLarge)),
        ?trailing,
      ],
    ),
  );
}

/// Color strip, weekday with date, below it the time.
class _When extends StatelessWidget {
  const _When({
    required this.occurrence,
    required this.event,
    required this.color,
  });

  final Occurrence? occurrence;
  final CalendarEvent event;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final when = switch (occurrence) {
      final item? => occurrenceWhen(l, locale, item),
      null => (date: '—', time: ''),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: .stretch,
        children: [
          Container(
            width: HiwiskiMetrics.calendarStripeWidth,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusBar)),
            ),
          ),
          const SizedBox(width: HiwiskiMetrics.space14),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: HiwiskiMetrics.space6,
              children: [
                Text(
                  when.date,
                  style: context.texts.bodyLarge?.copyWith(fontWeight: .w500),
                ),
                Text(
                  when.time,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
