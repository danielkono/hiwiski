import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/rich_text/view/markdown_text_controller.dart';
import '../../../../components/comments/view/comment_list.dart';
import '../../../../components/item_info/view/item_info.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/ui/info_bar.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/edit_actions.dart';
import '../../../../core/ui/info_delete_section.dart';
import '../../../../core/ui/info_property.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/recurrence_dialog.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/states.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../domain/calendar/occurrence.dart';
import '../../../../domain/common/item_ref.dart';
import '../../event_sheet/view/event_sheet.dart';
import '../../view/reminder_picker.dart';
import '../../view/series_scope_dialog.dart';
import '../event_view_model.dart';
import 'event_body.dart';

/// Stands where the number will: created offline, an event has none yet.
const _noKey = '—';

/// An event, for reading.
///
/// Color strip, weekday with date, time. Rows with a symbol: location (with a jump to
/// the map), reminder, attendees; below that the note with reference chips and the
/// comments. To the right or below, the info bar. "Edit" turns the page into the
/// event's fields.
///
/// **Tapping an event opens this view, not the form.** Before, every tap jumped into
/// editing — even for subscription events that nobody can change.
class EventScreen extends ConsumerWidget {
  const EventScreen({super.key, required this.eventId, this.at});

  final String eventId;

  /// The start of the intended occurrence of a series; without it, the first one.
  final DateTime? at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final header = PageHeader(
      title: l.calEventFallback,
      onBack: () => _back(context),
    );
    return ref
        .watch(eventViewModelProvider(eventId))
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) => state == null
              ? HiwiskiPage(
                  header: header,
                  body: EmptyState(
                    icon: HiwiskiSymbols.event,
                    message: l.stateGone,
                  ),
                )
              : _EventPage(at: at, eventId: eventId, state: state),
        );
  }

  static void _back(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      const CalendarRoute().go(context);
    }
  }
}

class _EventPage extends ConsumerStatefulWidget {
  const _EventPage({
    required this.at,
    required this.eventId,
    required this.state,
  });

  final DateTime? at;
  final String eventId;
  final EventState state;

  @override
  ConsumerState<_EventPage> createState() => _EventPageState();
}

class _EventPageState extends ConsumerState<_EventPage> {
  /// The event's fields are open on the page.
  bool _editing = false;

  /// The header's "Save" reads the fields through this.
  final _form = GlobalKey<EventFormState>();

  @override
  Widget build(BuildContext context) {
    final at = widget.at;
    final eventId = widget.eventId;
    final state = widget.state;
    final l = L.of(context);
    final row = state.event;
    final calendar = state.calendar;
    final readOnly = state.readOnly;
    final occurrence = occurrenceNear(row, at: at);
    final wide = InfoBar.besideContent(context);
    final padding = Breakpoint.of(context).pagePadding;
    final color = context.tokens.accent(
      accentOf(calendar?.colorToken ?? ColorTokens.blue),
    );

    void edit() => setState(() => _editing = true);

    final infoBar = ItemInfo(
      item: ItemRef.event(row.id),
      editable: !readOnly,
      properties: [
        InfoProperty(
          label: l.propCalendar,
          value: calendar?.name ?? _noKey,
          dot: color,
          onTap: readOnly ? null : edit,
        ),
        InfoProperty(
          label: l.propRepeat,
          value: describeRecurrence(
            context,
            row.rrule,
            occurrence?.start ?? clock.now(),
          ),
          onTap: readOnly ? null : edit,
        ),
        InfoProperty(
          label: l.propReminder,
          value: eventReminderLabel(
            l,
            row.reminderMinutes,
            calendar?.defaultReminderMinutes,
          ),
          onTap: readOnly ? null : edit,
        ),
      ],
      actions: [
        if (!readOnly)
          InfoDeleteSection(
            label: l.calDeleteEvent,
            // It asks on its own — for a series which occurrences, otherwise whether.
            onDelete: () async {
              if (await _deleteAsking(context, ref, row, occurrence) &&
                  context.mounted) {
                EventScreen._back(context);
              }
            },
          ),
      ],
    );

    final content = ListView(
      padding: padding.add(const .only(bottom: HiwiskiMetrics.space32)),
      children: [
        if (_editing)
          // The page becomes its fields, as a task and a wiki page do.
          EventForm(
            key: _form,
            event: row,
            occurrence: occurrence,
            onClosed: () => setState(() => _editing = false),
          )
        else ...[
          EventBody(eventId: eventId, at: at),
          const SizedBox(height: HiwiskiMetrics.space24),
          CommentList(item: ItemRef.event(row.id)),
        ],
        if (!wide) infoBar,
      ],
    );

    return HiwiskiPage(
      header: PageHeader(
        title: row.title,
        // "EV-3 · Family" — the citable key, then the calendar as a link to its
        // overview. Created offline means: no key yet.
        entityKey: row.entityKey ?? _noKey,
        crumbs: [
          HeaderCrumb(
            label: calendar?.name ?? l.navCalendar,
            onTap: () => const CalendarRoute().go(context),
          ),
        ],
        onBack: () => EventScreen._back(context),
        trailing: [
          if (!readOnly)
            EditActions(
              editing: _editing,
              onEdit: edit,
              onSave: () => _form.currentState?.save(),
              // Greyed out while images are still being added to the note.
              saveBlocked: MarkdownTextController.addingImagesAnywhere,
              onCancel: () => setState(() => _editing = false),
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth:
                      HiwiskiMetrics.contentMaxWidth +
                      2 * HiwiskiMetrics.space32,
                ),
                child: content,
              ),
            ),
          ),
          if (wide) infoBar,
        ],
      ),
    );
  }
}

/// Deletes an event — from the info bar at the bottom of the event screen.
///
/// On an occurrence of a series it asks first: only this one, this and all following,
/// or the whole series. Returns whether something was deleted.
Future<bool> _deleteAsking(
  BuildContext context,
  WidgetRef ref,
  CalendarEvent event,
  Occurrence? occurrence,
) async {
  if ((event.rrule ?? '').isNotEmpty && occurrence?.originalStart != null) {
    final scope = await askSeriesScope(context, deleting: true);
    if (scope == null) return false;
    await ref
        .read(eventViewModelProvider(event.id).notifier)
        .delete(event, occurrence: occurrence, scope: scope);
    return true;
  }
  final l = L.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.calDeleteEventConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.actionDelete),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return false;
  await ref.read(eventViewModelProvider(event.id).notifier).delete(event);
  return true;
}
