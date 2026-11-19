import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../components/sharing/view/share_draft_section.dart';
import '../../../../components/tags/view/tags_section.dart';
import '../../../../core/api/generated/export.dart' hide Mutation;
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/common/app_names.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_picker.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/pick_files.dart';
import '../../../../core/ui/picker_field.dart';
import '../../../../core/ui/hiwiski_sheet.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../domain/calendar/calendar_kinds.dart';
import '../../../../domain/calendar/import_target.dart';
import '../../../../domain/common/change.dart';
import '../../../../domain/tags/tag.dart';
import '../../view/calendar_keys.dart';
import '../../view/reminder_picker.dart';
import '../manage_calendars_view_model.dart';

/// An address worth checking already: a scheme and a host with a dot.
final _calendarAddress = RegExp(
  r'^(https?|webcal)://\S+\.\S+',
  caseSensitive: false,
);

/// "If the address looks like tasks" -- what it contains then.
const _taskHints = ['todo', 'task'];

const _icsExtension = 'ics';
final _icsSuffix = RegExp(r'\.ics$');

// Where an import reads from, and what it writes into.
const _sourceLink = 'LINK';
const _sourceFile = 'FILE';
const _targetNew = 'NEW';
const _targetExisting = 'EXISTING';

/// "New calendar" — name, color picker (eight dots), visibility.
///
/// While creating, visibility is a draft in the sheet (`ShareDraftSection`); on a
/// finished calendar it is the share sheet, **the same on every item**.
///
/// [deletable]: whether the sheet offers "Delete" — the calendar's owner only.
Future<void> showCalendarSheet(
  BuildContext context, {
  Calendar? calendar,
  bool deletable = false,
}) {
  final l = L.of(context);
  return showHiwiskiSheet<void>(
    context: context,
    title: calendar == null ? l.calNewCalendar : l.calCalendarName,
    builder: (context) =>
        _CalendarBody(calendar: calendar, deletable: deletable),
  );
}

class _CalendarBody extends ConsumerStatefulWidget {
  const _CalendarBody({this.calendar, this.deletable = false});

  final Calendar? calendar;
  final bool deletable;

  @override
  ConsumerState<_CalendarBody> createState() => _CalendarBodyState();
}

class _CalendarBodyState extends ConsumerState<_CalendarBody> {
  late final TextEditingController _name = TextEditingController(
    text: widget.calendar?.name ?? '',
  );
  late String _color = widget.calendar?.colorToken ?? ColorTokens.blue;
  late Set<String> _tags = tagIdsOf(widget.calendar?.tags ?? '').toSet();
  late int? _defaultReminder = widget.calendar?.defaultReminderMinutes;
  List<WriteShare> _shares = [];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Set while a save runs: a second tap wrote everything twice.
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _saveOnce();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOnce() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final calendar = widget.calendar;
    if (calendar == null) {
      await createCalendarMutation.run(
        ref,
        (tsx) => tsx
            .get(manageCalendarsViewModelProvider.notifier)
            .createCalendar(
              name: name,
              colorToken: _color,
              tags: _tags.toList(),
              defaultReminderMinutes: _defaultReminder,
              shares: _shares,
            ),
      );
    } else {
      await ref
          .read(manageCalendarsViewModelProvider.notifier)
          .updateCalendar(
            calendar,
            name: name,
            colorToken: _color,
            tags: _tags.toList(),
            defaultReminderMinutes: Change(_defaultReminder),
          );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l = L.of(context);
    final calendar = widget.calendar;
    if (calendar == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.calDeleteCalendar),
        content: Text(l.calDeleteCalendarBody),
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
    if (!(confirmed ?? false)) return;
    await ref
        .read(manageCalendarsViewModelProvider.notifier)
        .deleteCalendar(calendar);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        TextField(
          key: CalendarKeys.calendarName,
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(labelText: l.calCalendarName),
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        Text(l.calColor, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        ColorPicker(
          selected: _color,
          onSelected: (value) => setState(() => _color = value),
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        // For every event in it — also imported and subscribed ones (calendar_tags.dart).
        TagsSection(
          raw: _tags.join(','),
          onChanged: (next) => setState(() => _tags = next.toSet()),
        ),
        Text(
          l.calTagsHint,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        // For every event without a reminder of its own — existing ones included
        // (calendar_reminders.dart).
        PickerField(
          key: CalendarKeys.calendarDefaultReminder,
          icon: HiwiskiSymbols.notifications,
          label: l.calDefaultReminder,
          value: reminderLabel(l, _defaultReminder),
          onOpen: (field) async {
            final chosen = await pickReminder(
              field,
              current: _defaultReminder,
              forCalendar: true,
            );
            if (chosen != null && mounted) {
              setState(() => _defaultReminder = chosen.minutes);
            }
          },
        ),
        Padding(
          padding: const .only(top: HiwiskiMetrics.space4),
          child: Text(
            l.calDefaultReminderHint,
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
        if (widget.calendar == null) ...[
          const SizedBox(height: HiwiskiMetrics.space20),
          ShareDraftSection(
            itemType: EntityTypes.calendar,
            shares: _shares,
            onChanged: (next) => setState(() => _shares = next),
          ),
        ],
        SheetActions(
          children: [
            if (widget.calendar != null && widget.deletable)
              TextButton(
                onPressed: _delete,
                style: TextButton.styleFrom(
                  foregroundColor: context.scheme.error,
                ),
                child: Text(l.actionDelete),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              // "Create" for something new, "Save" for a change.
              child: Text(
                widget.calendar == null ? l.actionCreate : l.actionSave,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Add subscription" — ICS address, name, interval, color, visibility, **target kind**
/// (locked afterwards), and the hint.
Future<void> showSubscriptionSheet(BuildContext context) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).calAddSubscription,
    builder: (context) => const _SubscriptionBody(),
  );
}

class _SubscriptionBody extends ConsumerStatefulWidget {
  const _SubscriptionBody();

  @override
  ConsumerState<_SubscriptionBody> createState() => _SubscriptionBodyState();
}

class _SubscriptionBodyState extends ConsumerState<_SubscriptionBody> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  String _color = ColorTokens.teal;
  String _interval = SyncIntervals.daily;
  String _target = SubscriptionTargets.event;

  /// Whether the member picked the target — from then on it is theirs, not a guess.
  bool _targetPicked = false;

  /// The address the preview shows, once checked — so nobody subscribes to the
  /// wrong file.
  String? _checked;

  /// The preview loads by itself shortly after the address stops changing — a button
  /// alone was overlooked, and then there was no preview at all.
  Timer? _autoCheck;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _url.addListener(_urlChanged);
  }

  void _urlChanged() {
    // The listener also fires on cursor moves; only a changed address counts.
    if (_url.text == _lastText) return;
    _lastText = _url.text;
    _guessTarget();
    if (_checked != null) setState(() => _checked = null);
    _autoCheck?.cancel();
    if (_calendarAddress.hasMatch(_url.text.trim())) {
      _autoCheck = Timer(const Duration(milliseconds: 800), _check);
    }
  }

  void _check() {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    _autoCheck?.cancel();
    setState(() => _checked = url);
  }

  @override
  void dispose() {
    _autoCheck?.cancel();
    _url
      ..removeListener(_urlChanged)
      ..dispose();
    _name.dispose();
    super.dispose();
  }

  /// "If the address looks like tasks, the app suggests `TASK`."
  ///
  /// Only a suggestion: it used to run on every cursor move and set the target back
  /// over the member's own choice — which is locked once the subscription exists.
  void _guessTarget() {
    if (_targetPicked) return;
    final url = _url.text.toLowerCase();
    final looksLikeTasks = _taskHints.any(url.contains);
    final guess = looksLikeTasks
        ? SubscriptionTargets.task
        : SubscriptionTargets.event;
    if (guess != _target) setState(() => _target = guess);
  }

  Future<void> _create() async {
    // A second tap while it ran wrote everything twice.
    if (ref.read(createSubscriptionMutation).isPending) return;
    final url = _url.text.trim();
    final name = _name.text.trim().isEmpty ? url : _name.text.trim();
    if (url.isEmpty) return;
    await createSubscriptionMutation.run(
      ref,
      (tsx) => tsx
          .get(manageCalendarsViewModelProvider.notifier)
          .createSubscription(
            name: name,
            url: url,
            colorToken: _color,
            syncInterval: _interval,
            targetKind: _target,
          ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final checked = _checked;
    final (checking, previewError, preview) = switch (checked) {
      null => (false, null, null),
      final url =>
        ref
            .watch(calendarPreviewViewModelProvider(url: url))
            .when(
              skipLoadingOnReload: true,
              loading: () => (true, null, null),
              error: (error, _) => (
                false,
                failureText(context, HiwiskiFailure.from(error)),
                null,
              ),
              data: (preview) => (false, null, preview),
            ),
    };
    if (checked != null) {
      // The calendar's own name as a suggestion, unless one was typed.
      ref.listen(calendarPreviewViewModelProvider(url: checked), (_, next) {
        if (next.value?.name case final name? when _name.text.trim().isEmpty) {
          _name.text = name;
        }
      });
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        TextField(
          key: CalendarKeys.subscriptionUrl,
          controller: _url,
          autofocus: true,
          keyboardType: .url,
          decoration: InputDecoration(
            labelText: l.calSubscriptionUrl,
            errorText: previewError,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: checking ? null : _check,
            icon: checking
                ? const SizedBox.square(
                    dimension: HiwiskiMetrics.icon16,
                    child: CircularProgressIndicator(
                      strokeWidth: HiwiskiMetrics.strokeBold,
                    ),
                  )
                : const Icon(
                    HiwiskiSymbols.search,
                    size: HiwiskiMetrics.icon18,
                  ),
            label: Text(l.calSubscriptionCheck),
          ),
        ),
        if (preview != null) _PreviewCard(preview: preview),
        const SizedBox(height: HiwiskiMetrics.space12),
        TextField(
          key: CalendarKeys.subscriptionName,
          controller: _name,
          decoration: InputDecoration(labelText: l.calCalendarName),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        DropdownButtonFormField<String>(
          initialValue: _interval,
          decoration: InputDecoration(labelText: l.calSubscriptionInterval),
          items: [
            DropdownMenuItem(
              value: SyncIntervals.hourly,
              child: Text(l.calIntervalHourly),
            ),
            DropdownMenuItem(
              value: SyncIntervals.daily,
              child: Text(l.calIntervalDaily),
            ),
            DropdownMenuItem(
              value: SyncIntervals.weekly,
              child: Text(l.calIntervalWeekly),
            ),
          ],
          onChanged: (value) =>
              setState(() => _interval = value ?? SyncIntervals.daily),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        Text(l.calSubscriptionTarget, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: SubscriptionTargets.event,
              label: Text(l.calSubscriptionTargetEvent),
            ),
            ButtonSegment(
              value: SubscriptionTargets.task,
              label: Text(l.calSubscriptionTargetTask),
            ),
          ],
          selected: {_target},
          onSelectionChanged: (value) => setState(() {
            _target = value.firstOrNull ?? _target;
            _targetPicked = true;
          }),
        ),
        const SizedBox(height: HiwiskiMetrics.space4),
        Text(
          l.calSubscriptionTargetLocked,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        Text(l.calColor, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        ColorPicker(
          selected: _color,
          onSelected: (value) => setState(() => _color = value),
        ),
        const SizedBox(height: HiwiskiMetrics.space16),
        Text(
          l.calSubscriptionNote,
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
        SheetActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: ref.watch(createSubscriptionMutation).isPending
                  ? null
                  : _create,
              child: Text(l.actionCreate),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Create link" — name, choice of included calendars, content.
Future<void> showFeedSheet(BuildContext context) {
  return showHiwiskiSheet<void>(
    context: context,
    title: L.of(context).calNewFeed,
    builder: (context) => const _FeedBody(),
  );
}

class _FeedBody extends ConsumerStatefulWidget {
  const _FeedBody();

  @override
  ConsumerState<_FeedBody> createState() => _FeedBodyState();
}

class _FeedBodyState extends ConsumerState<_FeedBody> {
  final _name = TextEditingController();
  final _selected = <String>{};
  String _mode = FeedContentModes.full;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    // A second tap while it ran wrote everything twice.
    if (ref.read(createFeedMutation).isPending) return;
    if (_selected.isEmpty) return;
    await createFeedMutation.run(
      ref,
      (tsx) => tsx
          .get(manageCalendarsViewModelProvider.notifier)
          .createFeed(
            name: _name.text.trim().isEmpty
                ? AppNames.product
                : _name.text.trim(),
            calendarIds: _selected.toList(),
            contentMode: _mode,
          ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final calendars =
        ref.watch(manageCalendarsViewModelProvider).value?.all ?? const [];

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        TextField(
          key: CalendarKeys.feedName,
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(labelText: l.calFeedName),
        ),
        const SizedBox(height: HiwiskiMetrics.space20),
        Text(l.calFeedCalendars, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        if (calendars.isEmpty)
          Text(
            l.calFeedNoCalendars,
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: HiwiskiMetrics.space8,
            runSpacing: HiwiskiMetrics.space8,
            children: [
              for (final calendar in calendars)
                FilterChip(
                  avatar: Container(
                    width: HiwiskiMetrics.dotMedium,
                    height: HiwiskiMetrics.dotMedium,
                    decoration: BoxDecoration(
                      color: context.tokens.accent(
                        accentOf(calendar.colorToken),
                      ),
                      shape: .circle,
                    ),
                  ),
                  label: Text(calendar.name),
                  selected: _selected.contains(calendar.id),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selected.add(calendar.id);
                    } else {
                      _selected.remove(calendar.id);
                    }
                  }),
                ),
            ],
          ),
        const SizedBox(height: HiwiskiMetrics.space20),
        Text(l.calFeedContent, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: FeedContentModes.full,
              label: Text(l.calFeedContentFull),
            ),
            // "free/busy only": Grandma sees that something is on, not what.
            ButtonSegment(
              value: FeedContentModes.busy,
              label: Text(l.calFeedContentBusy),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (value) =>
              setState(() => _mode = value.firstOrNull ?? _mode),
        ),
        SheetActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: ref.watch(createFeedMutation).isPending
                  ? null
                  : _create,
              child: Text(l.actionCreate),
            ),
          ],
        ),
      ],
    );
  }
}

/// What a checked address holds: the count and the next few events.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final SubscriptionPreview preview;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    String when(PreviewEvent event) {
      final date = event.startsAt?.toLocal() ?? event.startDate;
      if (date == null) return '';
      return event.allDay || event.startsAt == null
          ? DateFormat.yMMMEd(locale).format(date)
          : DateFormat.yMMMEd(locale).add_Hm().format(date);
    }

    return Container(
      margin: const .only(top: HiwiskiMetrics.space4),
      padding: const .all(HiwiskiMetrics.space12),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainer,
        borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text(
            [
              ?preview.name,
              l.calSubscriptionEventCount(preview.eventCount),
            ].join(' · '),
            style: context.texts.titleSmall,
          ),
          if (preview.upcoming.isEmpty)
            Text(
              l.calSubscriptionNothingUpcoming,
              style: context.texts.bodySmall?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            )
          else
            for (final event in preview.upcoming)
              Padding(
                padding: const .only(top: HiwiskiMetrics.space4),
                child: Row(
                  spacing: HiwiskiMetrics.space8,
                  children: [
                    Expanded(child: Text(event.title, overflow: .ellipsis)),
                    Text(
                      when(event),
                      style: context.texts.bodySmall?.copyWith(
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

/// **Import an `.ics` file or address** — a one-off, not a subscription.
///
/// The source is a file read on the device or a link the server fetches **once**. A
/// preview shows what it holds before anything is written. The target is one of our
/// calendars or a new one — optionally **locked** like a subscription, so its events
/// stay as the file had them. Importing the same file again updates instead of doubling
/// (matched by UID).
Future<void> showIcsImportSheet(BuildContext context) => showHiwiskiSheet<void>(
  context: context,
  title: L.of(context).calImportTitle,
  builder: (context) => const _ImportBody(),
);

class _ImportBody extends ConsumerStatefulWidget {
  const _ImportBody();

  @override
  ConsumerState<_ImportBody> createState() => _ImportBodyState();
}

class _ImportBodyState extends ConsumerState<_ImportBody> {
  final _url = TextEditingController();
  final _name = TextEditingController();

  /// `FILE` or `LINK` — whichever was used last; `null` before either was.
  String? _source;
  String? _fileName;
  String? _ics;

  /// A typed address loads its preview by itself once it stops changing — like the
  /// subscription sheet; there is no button to find.
  Timer? _autoLoad;
  String _lastUrl = '';

  @override
  void initState() {
    super.initState();
    _url.addListener(_urlChanged);
  }

  void _urlChanged() {
    // The listener also fires on cursor moves; only a changed address counts.
    final url = _url.text.trim();
    if (url == _lastUrl) return;
    _lastUrl = url;
    _autoLoad?.cancel();
    setState(() {
      _error = null;
      if (url.isNotEmpty) {
        _source = _sourceLink;
        _checked = null;
      } else if (_source == _sourceLink) {
        _source = _ics == null ? null : _sourceFile;
        _checked = null;
      }
    });
    if (url.isEmpty && _source == _sourceFile) {
      _loadPreview();
    } else if (_calendarAddress.hasMatch(url)) {
      _autoLoad = Timer(const Duration(milliseconds: 800), _loadPreview);
    }
  }

  void _clearFile() => setState(() {
    _fileName = null;
    _ics = null;
    _checked = null;
    _error = null;
    _source = _url.text.trim().isEmpty ? null : _sourceLink;
  });

  /// `EXISTING` or `NEW`.
  String? _target;
  String? _calendarId;
  String _color = ColorTokens.green;
  bool _locked = true;

  /// The source the preview shows, once it is checked.
  ({String? url, String? ics})? _checked;

  /// Why the import failed.
  String? _error;

  @override
  void dispose() {
    _autoLoad?.cancel();
    _url
      ..removeListener(_urlChanged)
      ..dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await pickFiles(
      type: .custom,
      allowedExtensions: [_icsExtension],
    );
    if (picked.isEmpty || !mounted) return;
    final file = picked.first;
    final ics = utf8.decode(
      await file.xFile.readAsBytes(),
      allowMalformed: true,
    );
    if (!mounted) return;
    _autoLoad?.cancel();
    setState(() {
      _fileName = file.name;
      _ics = ics;
      _source = _sourceFile;
    });
    // The file wins: an address typed before would otherwise look like the source.
    _url.clear();
    _loadPreview();
  }

  /// What the file or the address holds — before anything is written.
  void _loadPreview() {
    final url = _url.text.trim();
    final source = _source;
    if (source == null ||
        (source == _sourceFile ? _ics == null : url.isEmpty)) {
      return;
    }
    _autoLoad?.cancel();
    setState(() {
      _error = null;
      _checked = source == _sourceFile
          ? (url: null, ics: _ics)
          : (url: url, ics: null);
    });
  }

  bool _ready(SubscriptionPreview? preview, {required bool busy}) =>
      _source != null &&
      preview != null &&
      !busy &&
      (_target == _targetNew
          ? _name.text.trim().isNotEmpty
          : _calendarId != null);

  Future<void> _import() async {
    // A second tap while it ran imported everything twice.
    if (ref.read(importIcsMutation).isPending) return;
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ImportTarget? target = switch ((_target, _calendarId)) {
      (_targetNew, _) => NewCalendar(
        name: _name.text.trim(),
        colorToken: _color,
        locked: _locked,
      ),
      (_, final calendarId?) => ExistingCalendar(calendarId),
      _ => null,
    };
    if (target == null) return;
    setState(() => _error = null);
    try {
      final result = _source == _sourceFile
          ? await importIcsMutation.run(
              ref,
              (tsx) => tsx
                  .get(manageCalendarsViewModelProvider.notifier)
                  .importIcs(target, ics: _ics),
            )
          : await importIcsMutation.run(
              ref,
              (tsx) => tsx
                  .get(manageCalendarsViewModelProvider.notifier)
                  .importIcs(target, url: _url.text.trim()),
            );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l.calImportDone(result.importedCount, result.updatedCount),
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on HiwiskiFailure catch (failure) {
      if (mounted) {
        setState(() => _error = failureText(context, failure));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final checked = _checked;
    final (loading, previewError, preview) = switch (checked) {
      null => (false, null, null),
      (:final url, :final ics) =>
        ref
            .watch(calendarPreviewViewModelProvider(url: url, ics: ics))
            .when(
              skipLoadingOnReload: true,
              loading: () => (true, null, null),
              error: (error, _) => (
                false,
                failureText(context, HiwiskiFailure.from(error)),
                null,
              ),
              data: (preview) => (false, null, preview),
            ),
    };
    if (checked case (:final url, :final ics)) {
      // The calendar's own name — or the file's — as the new calendar's name.
      ref.listen(calendarPreviewViewModelProvider(url: url, ics: ics), (
        _,
        next,
      ) {
        if (next.value case final found? when _name.text.trim().isEmpty) {
          _name.text =
              found.name ?? _fileName?.replaceAll(_icsSuffix, '') ?? '';
        }
      });
    }
    final busy = ref.watch(importIcsMutation).isPending || loading;
    final error = _error ?? previewError;
    // Only our own calendars: a subscribed one belongs to its source. A locked import
    // takes a further import — that is how it stays current.
    final calendars = [
      for (final managed
          in ref.watch(manageCalendarsViewModelProvider).value?.calendars ??
              const [])
        managed.calendar,
    ];
    final target =
        _target ?? (calendars.isEmpty ? _targetNew : _targetExisting);
    _target = target;
    if (_calendarId != null && !calendars.any((row) => row.id == _calendarId)) {
      _calendarId = null;
    }
    _calendarId ??=
        calendars.where((row) => row.kind != kindImported).firstOrNull?.id ??
        calendars.firstOrNull?.id;

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(l.calImportSource, style: context.tokens.text.sectionLabel),
        const SizedBox(height: HiwiskiMetrics.space8),
        // Link and file side by side, no switch between them: whichever is used last is
        // the source.
        TextField(
          key: CalendarKeys.importUrl,
          controller: _url,
          keyboardType: .url,
          decoration: InputDecoration(
            labelText: l.calSubscriptionUrl,
            suffixIcon: _url.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(
                      HiwiskiSymbols.close,
                      size: HiwiskiMetrics.icon18,
                    ),
                    tooltip: l.calImportClearLink,
                    onPressed: () => _url.clear(),
                  ),
          ),
          onSubmitted: (_) => _loadPreview(),
        ),
        if (_source == _sourceLink) ...[
          const SizedBox(height: HiwiskiMetrics.space4),
          Text(
            l.calImportLinkOnce,
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: HiwiskiMetrics.space8),
        Row(
          spacing: HiwiskiMetrics.space12,
          children: [
            Text(
              l.calImportOr,
              style: context.texts.bodyMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
            Flexible(
              child: _source == _sourceFile && _fileName != null
                  ? InputChip(
                      key: CalendarKeys.importFile,
                      avatar: const Icon(
                        HiwiskiSymbols.upload,
                        size: HiwiskiMetrics.icon18,
                      ),
                      label: Text(_fileName ?? '', overflow: .ellipsis),
                      onPressed: busy ? null : _pickFile,
                      onDeleted: busy ? null : _clearFile,
                    )
                  : OutlinedButton.icon(
                      key: CalendarKeys.importPickFile,
                      icon: const Icon(
                        HiwiskiSymbols.upload,
                        size: HiwiskiMetrics.icon18,
                      ),
                      label: Text(l.calImportPickFile),
                      onPressed: busy ? null : _pickFile,
                    ),
            ),
          ],
        ),
        if (busy) ...[
          const SizedBox(height: HiwiskiMetrics.space8),
          const LinearProgressIndicator(),
        ],
        if (error case final message?)
          Padding(
            padding: const .only(top: HiwiskiMetrics.space8),
            child: Text(
              message,
              style: context.texts.bodySmall?.copyWith(
                color: context.scheme.error,
              ),
            ),
          ),
        if (preview != null) ...[
          const SizedBox(height: HiwiskiMetrics.space8),
          _PreviewCard(preview: preview),
          const SizedBox(height: HiwiskiMetrics.space20),
          Text(l.calImportTarget, style: context.tokens.text.sectionLabel),
          const SizedBox(height: HiwiskiMetrics.space8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: _targetExisting,
                label: Text(l.calImportTargetExisting),
                enabled: calendars.isNotEmpty,
              ),
              ButtonSegment(
                value: _targetNew,
                label: Text(l.calImportTargetNew),
              ),
            ],
            selected: {target},
            onSelectionChanged: (value) =>
                setState(() => _target = value.firstOrNull ?? _target),
          ),
          const SizedBox(height: HiwiskiMetrics.space12),
          if (target == _targetExisting)
            DropdownButtonFormField<String>(
              key: CalendarKeys.importCalendar,
              initialValue: _calendarId,
              decoration: InputDecoration(labelText: l.calCalendar),
              items: [
                for (final calendar in calendars)
                  DropdownMenuItem(
                    value: calendar.id,
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        Icon(
                          HiwiskiSymbols.circle,
                          size: HiwiskiMetrics.icon16,
                          color: context.tokens.accent(
                            accentOf(calendar.colorToken),
                          ),
                        ),
                        const SizedBox(width: HiwiskiMetrics.space8),
                        Text(calendar.name),
                        if (calendar.kind == kindImported) ...[
                          const SizedBox(width: HiwiskiMetrics.space4),
                          const Icon(
                            HiwiskiSymbols.lock,
                            size: HiwiskiMetrics.icon16,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _calendarId = value),
            )
          else ...[
            TextField(
              key: CalendarKeys.importName,
              controller: _name,
              decoration: InputDecoration(labelText: l.calCalendarName),
            ),
            const SizedBox(height: HiwiskiMetrics.space12),
            ColorPicker(
              selected: _color,
              onSelected: (value) => setState(() => _color = value),
            ),
            const SizedBox(height: HiwiskiMetrics.space8),
            SwitchListTile(
              key: CalendarKeys.importLocked,
              contentPadding: EdgeInsets.zero,
              value: _locked,
              onChanged: (value) => setState(() => _locked = value),
              title: Text(l.calImportLocked),
              subtitle: Text(l.calImportLockedHint),
            ),
          ],
        ],
        SheetActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            // Follows the name field: a new calendar needs one.
            ListenableBuilder(
              listenable: _name,
              builder: (context, _) => FilledButton(
                key: CalendarKeys.importSubmit,
                onPressed: _ready(preview, busy: busy) ? _import : null,
                child: Text(l.calImportSubmit),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
