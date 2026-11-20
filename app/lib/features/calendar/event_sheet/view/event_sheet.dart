import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../components/assignees/view/assignees.dart';
import '../../../../components/links/view/references_section.dart';
import '../../../../components/sharing/view/share_draft_section.dart';
import '../../../../components/sharing/view/share_sheet.dart';
import '../../../../components/tags/view/tag_field.dart';
import '../../../../components/rich_text/view/rich_text_editor.dart';
import '../../../../components/rich_text/view/markdown_text_controller.dart';
import '../../../../core/api/generated/export.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/field_pair.dart';
import '../../../../core/ui/loading_strip.dart';
import '../../../../core/ui/notice_bar.dart';
import '../../../../core/ui/choice_picker.dart';
import '../../../../core/ui/picker_field.dart';
import '../../../../core/ui/recurrence_dialog.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../domain/calendar/calendar_reminders.dart';
import '../../../../domain/calendar/event_draft.dart';
import '../../../../domain/calendar/occurrence.dart';
import '../../../../domain/calendar/reschedule.dart';
import '../../../../domain/common/item_ref.dart';
import '../../view/calendar_keys.dart';
import '../../view/reminder_picker.dart';
import '../../view/series_scope_dialog.dart';
import '../event_sheet_view_model.dart';

/// "New event / Edit event" — as a sheet or a dialog.
///
/// Title · All day · Start · Time · Calendar · Repeat · Reminder · Location ·
/// Note · Assigned · Share.
Future<void> showEventSheet(
  BuildContext context, {
  CalendarEvent? event,
  Occurrence? occurrence,
  DateTime? day,
  DateTime? start,
  String? calendarId,
}) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L
        .of(context)
        .let((l) => event == null ? l.calNewEventTitle : l.calEditEventTitle),
    builder: (context) => EventForm(
      event: event,
      occurrence: occurrence,
      day: day,
      start: start,
      calendarId: calendarId,
    ),
  );
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// The fields of an event — in the sheet for a new one, and on the event's own page
/// while it is edited there.
///
/// **An event is edited where it is read**, like a task, a list and a wiki page: "Edit"
/// in its header turns the page into these fields, and "Cancel" and "Save" stand where
/// "Edit" was ([onClosed] set; the page calls [EventFormState.save]). It used to open
/// this form as a dialog over the page — the only item that did.
class EventForm extends ConsumerStatefulWidget {
  const EventForm({
    super.key,
    this.event,
    this.occurrence,
    this.day,
    this.start,
    this.calendarId,
    this.onClosed,
  });

  /// Set on the event's page: called when the form is done, saved or not, instead of
  /// closing a sheet. The page then has the buttons, and the info bar beside the form
  /// has sharing and the references.
  final VoidCallback? onClosed;

  final CalendarEvent? event;
  final Occurrence? occurrence;
  final DateTime? day;

  /// A new event at exactly this time, for [weekDefaultMinutes] — a tap into the
  /// week's hours.
  final DateTime? start;
  final String? calendarId;

  @override
  ConsumerState<EventForm> createState() => EventFormState();
}

class EventFormState extends ConsumerState<EventForm> {
  final _title = TextEditingController();
  final _titleFocus = FocusNode();
  final _titleKey = GlobalKey();
  final _timeKey = GlobalKey();
  final _location = TextEditingController();
  final _note = MarkdownTextController();
  final _noteFocus = FocusNode();

  late bool _allDay;
  late DateTime _start;
  late DateTime _end;
  String? _calendarId;
  String? _rrule;

  /// The repeat rule as loaded or last chosen, and the day it was meant for. A new
  /// start date moves the rule along from there, as a drop on that day in the week
  /// view does ([ruleAfterMove]), so the form shows the rule that will be saved.
  /// Counted from there and not from the date picked before: Monday and Wednesday,
  /// moved from Monday to Wednesday, are Wednesday alone — moved on to Thursday they
  /// are Wednesday and Thursday again.
  ({String rule, DateTime day})? _chosenRule;
  int? _reminderMinutes;
  final _attendees = <String>{};
  Set<String> _tags = {};
  List<WriteShare> _shares = [];

  /// Set by a save that failed validation — the field turns red and says why.
  String? _titleError;
  String? _timeError;

  @override
  void initState() {
    super.initState();
    final event = widget.event;

    if ((event, widget.start) case (null, final start?)) {
      _allDay = false;
      _start = start;
      _end = start.add(const Duration(minutes: weekDefaultMinutes));
      _calendarId = widget.calendarId;
      return;
    }

    if (event == null) {
      // "A new event lands on the **selected** day, not on today."
      final base = widget.day ?? clock.now();
      final now = clock.now();
      _allDay = false;
      // The next full hour — but on the selected day: after 23:00 it would be 00:00
      // of the next one.
      _start = DateTime(
        base.year,
        base.month,
        base.day,
        math.min(now.hour + 1, 23),
      );
      final lastMinute = DateTime(base.year, base.month, base.day, 23, 59);
      final hourLater = _start.add(const Duration(hours: 1));
      _end = hourLater.isAfter(lastMinute) ? lastMinute : hourLater;
      _calendarId = widget.calendarId;
      return;
    }

    _title.text = event.title;
    _location.text = event.location ?? '';
    _note.text = event.description ?? '';
    _calendarId = event.calendarId;
    _rrule = event.rrule;
    _reminderMinutes = event.reminderMinutes;
    _attendees.addAll(event.attendees.split(',').where((id) => id.isNotEmpty));
    _tags = event.tags.split(',').where((id) => id.isNotEmpty).toSet();

    final occurrence = widget.occurrence;
    _allDay = event.timeForm == TimeForms.allDay;
    if (occurrence != null) {
      _start = occurrence.start;
      _end = occurrence.end;
    } else {
      _start =
          event.startsAt?.toLocal() ??
          event.startDate ??
          DateTime.tryParse(event.localStart ?? '') ??
          clock.now();
      _end =
          event.endsAt?.toLocal() ??
          event.endDate ??
          DateTime.tryParse(event.localEnd ?? '') ??
          _start.add(const Duration(hours: 1));
    }
    if (_rrule case final rule? when rule.isNotEmpty) {
      // The day the rule gave the occurrence, even where it was moved off it.
      _chosenRule = (rule: rule, day: occurrence?.originalStart ?? _start);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    _location.dispose();
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  bool get _isSeries => (_rrule ?? '').isNotEmpty;

  // --- The three time forms ------------------------------------------------------

  /// Which time form applies is decided by the switch and the repeat rule. A series
  /// keeps its wall-clock time across the daylight saving change.
  EventTime get _time => switch ((_allDay, _isSeries)) {
    (true, _) => AllDayEvent(_start, _end),
    (false, true) => RecurringEvent(_start, _end),
    (false, false) => TimedEvent(_start, _end),
  };

  EventDraft _draft() => .new(
    title: _title.text.trim(),
    description: _note.text.trim().isEmpty ? null : _note.text.trim(),
    location: _location.text.trim().isEmpty ? null : _location.text.trim(),
    rrule: (_rrule ?? '').isEmpty ? null : _rrule,
    attendees: _attendees.toList(),
    tags: _tags.toList(),
    reminderMinutes: _reminderMinutes,
    time: _time,
  );

  /// What a save needs: a title, and an end that is not before the start. Before, an
  /// empty title made "Save" silently do nothing.
  bool _validate() {
    final l = L.of(context);
    setState(() {
      _titleError = _title.text.trim().isEmpty ? l.validationRequired : null;
      _timeError = _end.isBefore(_start) ? l.calEndBeforeStart : null;
    });
    // A long sheet is scrolled down at "Save" — the field that is missing has to come
    // into view, or the red stays unseen and "Save" seems to do nothing.
    final first = switch ((_titleError, _timeError)) {
      (_?, _) => _titleKey,
      (null, _?) => _timeKey,
      (null, null) => null,
    };
    if (first != null) {
      if (first == _titleKey) _titleFocus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = first.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(
            target,
            alignment: 0.1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
    return _titleError == null && _timeError == null;
  }

  /// Set while a save runs: a second tap wrote everything twice.
  bool _saving = false;

  /// Leaves the form: back to the page it is on, or out of its sheet.
  void _close() {
    final onClosed = widget.onClosed;
    if (onClosed != null) {
      onClosed();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Validates and writes — the sheet's "Save", and the page header's.
  Future<void> save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _saveOnce();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOnce() async {
    if (!_validate()) return;
    // Read before the first `await`: after that the context is no longer safe.
    final defaultName = L.of(context).calDefaultCalendar;

    final event = widget.event;
    if (event == null) {
      await ref
          .read(eventSheetViewModelProvider.notifier)
          .create(
            calendarId: _calendarId,
            defaultCalendarName: defaultName,
            draft: _draft(),
            shares: _shares,
          );
      if (mounted) _close();
      return;
    }

    // "For a series event, saving asks: only this event / this and all
    // following / the whole series."
    final occurrence = widget.occurrence;
    SeriesScope scope = .wholeSeries;
    if (_isSeries && occurrence?.originalStart != null) {
      if (!mounted) return;
      final chosen = await askSeriesScope(context, deleting: false);
      if (chosen == null) return;
      scope = chosen;
    }
    await ref
        .read(eventSheetViewModelProvider.notifier)
        .edit(
          event,
          calendarId: _calendarId,
          defaultCalendarName: defaultName,
          occurrence: occurrence,
          series: _seriesDraft(event, occurrence),
          draft: _draft(),
          scope: scope,
        );
    if (mounted) _close();
  }

  /// The draft for the whole series. Opened from one occurrence, the series keeps its
  /// own start date and takes over only the change made to the time.
  EventDraft _seriesDraft(CalendarEvent event, Occurrence? occurrence) {
    final draft = _draft();
    if (occurrence == null) return draft;
    return switch ((draft.time, event.localStart, event.startDate)) {
      (final RecurringEvent time, final start?, _) => draft.withTime(
        time.reseed(
          seriesStart: DateTime.parse(start),
          opened: occurrence.start,
        ),
      ),
      (final AllDayEvent time, _, final startDate?) when _isSeries =>
        draft.withTime(
          time.reseed(seriesStart: startDate, opened: occurrence.start),
        ),
      _ => draft,
    };
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 10),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final moved = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      if (isStart) {
        final shift = moved.difference(_start);
        _start = moved;
        // The end moves along. Whoever moves the start means the event, not its
        // duration.
        _end = _end.add(shift);
        if (_chosenRule case (:final rule, :final day)?) {
          _rrule = ruleAfterMove(rule, original: day, target: moved);
        }
      } else {
        _end = moved.isBefore(_start) ? _start : moved;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final moved = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      if (isStart) {
        final shift = moved.difference(_start);
        _start = moved;
        _end = _end.add(shift);
      } else {
        _end = moved.isBefore(_start)
            ? _start.add(const Duration(minutes: 30))
            : moved;
      }
    });
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Start and end one after the other — one field "16:00 – 16:45" as in the design.
  Future<void> _pickTimes() async {
    await _pickTime(isStart: true);
    if (!mounted) return;
    await _pickTime(isStart: false);
  }

  Future<void> _pickCalendar(
    BuildContext field,
    List<Calendar> writable,
  ) async {
    final chosen = await pickChoice<String>(
      field,
      current: _calendarId,
      choices: [
        for (final calendar in writable)
          Choice(
            value: calendar.id,
            label: calendar.name,
            leading: _Dot(
              color: context.tokens.accent(accentOf(calendar.colorToken)),
            ),
          ),
      ],
    );
    if (chosen != null && mounted) setState(() => _calendarId = chosen.value);
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(eventSheetViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => const LoadingStrip(loading: true),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: _form,
      );

  Widget _form(EventSheetState state) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final writable = state.calendars;
    _calendarId ??= writable.isEmpty ? null : writable.first.id;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        // On the page the first field's label reaches above the field, and the
        // header ends right over it; a sheet has that room below its title.
        if (widget.onClosed != null)
          const SizedBox(height: HiwiskiMetrics.space8),
        KeyedSubtree(
          key: _titleKey,
          child: TextField(
            key: CalendarKeys.eventTitle,
            controller: _title,
            focusNode: _titleFocus,
            autofocus: widget.event == null,
            decoration: InputDecoration(
              labelText: l.calEventTitle,
              errorText: _titleError,
            ),
            textInputAction: .next,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space8),
        // "All day" as a row with a switch, symbol in front like the fields below.
        // One element to a screen reader: the switch is named by its row.
        MergeSemantics(
          child: InkWell(
            onTap: () => setState(() => _allDay = !_allDay),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: HiwiskiMetrics.minTapTarget,
              ),
              child: Row(
                children: [
                  Icon(
                    HiwiskiSymbols.schedule,
                    color: context.scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: HiwiskiMetrics.space12),
                  Expanded(
                    child: Text(l.calAllDay, style: context.texts.bodyLarge),
                  ),
                  Switch(
                    value: _allDay,
                    onChanged: (value) => setState(() => _allDay = value),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space12),
        FieldPair(
          key: _timeKey,
          children: [
            PickerField(
              icon: HiwiskiSymbols.event,
              label: l.calStart,
              value: DateFormat.yMEd(locale).format(_start),
              onTap: () => _pickDate(isStart: true),
            ),
            // "Time (omitted for all-day)". For all-day events the
            // end takes its place — a holiday has days, not a time.
            if (_allDay)
              PickerField(
                icon: HiwiskiSymbols.event,
                label: l.calEnd,
                value: DateFormat.yMEd(locale).format(_end),
                onTap: () => _pickDate(isStart: false),
                errorText: _timeError,
              )
            else
              PickerField(
                icon: HiwiskiSymbols.schedule,
                label: l.calTime,
                value:
                    '${DateFormat.Hm(locale).format(_start)} – '
                    '${DateFormat.Hm(locale).format(_end)}',
                onTap: _pickTimes,
                errorText: _sameDay(_start, _end) ? _timeError : null,
              ),
          ],
        ),
        // An event past midnight shows its end with the day added.
        if (!_allDay && !_sameDay(_start, _end)) ...[
          const SizedBox(height: HiwiskiMetrics.space12),
          PickerField(
            icon: HiwiskiSymbols.event,
            label: l.calEnd,
            value: DateFormat.yMEd(locale).format(_end),
            onTap: () => _pickDate(isStart: false),
            errorText: _timeError,
          ),
        ],
        const SizedBox(height: HiwiskiMetrics.space12),
        PickerField(
          icon: HiwiskiSymbols.calendarMonth,
          label: l.calCalendar,
          onOpen: (field) async {
            if (state.mayMove(widget.event)) {
              await _pickCalendar(field, writable);
            }
          },
          child: Builder(
            builder: (context) {
              final chosen = writable
                  .where((row) => row.id == _calendarId)
                  .firstOrNull;
              if (chosen == null) return const Text('—');
              return Row(
                spacing: HiwiskiMetrics.space8,
                children: [
                  _Dot(
                    color: context.tokens.accent(accentOf(chosen.colorToken)),
                  ),
                  Expanded(child: Text(chosen.name, overflow: .ellipsis)),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space12),
        FieldPair(
          children: [
            PickerField(
              icon: HiwiskiSymbols.repeat,
              label: l.calRepeat,
              value: describeRecurrence(context, _rrule, _start),
              onTap: () async {
                final result = await showRecurrenceDialog(
                  context: context,
                  rrule: _rrule,
                  start: _start,
                );
                if (result != null && mounted) {
                  setState(() {
                    _rrule = result.isEmpty ? null : result;
                    _chosenRule = result.isEmpty
                        ? null
                        : (rule: result, day: _start);
                  });
                }
              },
            ),
            PickerField(
              icon: HiwiskiSymbols.notifications,
              label: l.calReminder,
              value: eventReminderLabel(
                l,
                _reminderMinutes,
                _calendarDefault(),
              ),
              onOpen: _pickReminder,
            ),
          ],
        ),
        if (effectiveReminder(_reminderMinutes, _calendarDefault()) != null &&
            !state.remindersSupported)
          Padding(
            padding: const .only(top: HiwiskiMetrics.space4),
            child: Text(
              // The honest row instead of a switch that does nothing.
              l.calReminderNoBrowser,
              style: context.texts.bodySmall?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: HiwiskiMetrics.space12),
        TextField(
          key: CalendarKeys.eventLocation,
          controller: _location,
          decoration: InputDecoration(
            labelText: l.calLocation,
            prefixIcon: const Icon(
              HiwiskiSymbols.locationOn,
              size: HiwiskiMetrics.icon20,
            ),
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space12),
        // Written like a wiki page: Markdown with the insert bar, `#` suggesting
        // items, images — those once the event exists ("Note, links with # e.g.
        // #WIKI-3").
        RichTextEditor(
          controller: _note,
          focusNode: _noteFocus,
          carrier: switch (widget.event) {
            final event? => ItemRef.event(event.id),
            null => null,
          },
          fieldKey: CalendarKeys.eventNote,
          label: l.calNote,
          hint: l.linkHintNote,
          minLines: 3,
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        AssigneeChips(
          selected: _attendees,
          hint: l.calAssignedHint,
          onToggle: (id) => setState(() {
            _attendees.contains(id)
                ? _attendees.remove(id)
                : _attendees.add(id);
          }),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        TagField(
          selected: _tags,
          onChanged: (next) => setState(() => _tags = next),
        ),
        if (widget.event == null) ...[
          const SizedBox(height: HiwiskiMetrics.space16),
          ShareDraftSection(
            itemType: EntityTypes.event,
            shares: _shares,
            onChanged: (next) => setState(() => _shares = next),
          ),
        ],
        if (widget.event case final event? when widget.onClosed == null) ...[
          const Divider(height: HiwiskiMetrics.space24),
          if (state.shareable)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(HiwiskiSymbols.share),
              title: Text(l.shareTitle),
              onTap: () => showShareSheet(
                context,
                item: ItemRef(EntityTypes.event, event.id),
              ),
            ),
          const SizedBox(height: HiwiskiMetrics.space12),
          // The event's references in both directions. A dedicated event screen
          // with the full info bar is still pending -- until then
          // they sit here, where the event is edited.
          ReferencesSections(
            item: ItemRef.event(event.id),
            onOpen: (target) {
              // Secure the context first, then close the sheet: afterwards this sheet's
              // context is gone, and with it the way to the router.
              final router = Navigator.of(context, rootNavigator: true).context;
              Navigator.of(context).pop();
              openLinkTarget(router, ref, target);
            },
          ),
        ],
        if (widget.onClosed == null)
          SheetActions(
            children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.actionCancel),
              ),
              FilledButton(
                onPressed: _saving ? null : save,
                // "Create" for something new, "Save" for a change.
                child: Text(
                  widget.event == null ? l.actionCreate : l.actionSave,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _pickReminder(BuildContext field) async {
    final chosen = await pickReminder(
      field,
      current: _reminderMinutes,
      calendarDefault: _calendarDefault(),
    );
    if (chosen == null || !mounted) return;
    setState(() => _reminderMinutes = chosen.minutes);
  }

  /// The chosen calendar's default reminder — what an event without its own takes.
  int? _calendarDefault() => ref
      .read(eventSheetViewModelProvider)
      .value
      ?.defaultReminderOf(_calendarId);
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  static const size = HiwiskiMetrics.dotSmall;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: .circle),
  );
}
