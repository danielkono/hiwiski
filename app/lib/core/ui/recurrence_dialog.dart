import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/common/calendar_days.dart';
import '../../domain/common/recurrence_spec.dart';
import '../../domain/common/rrule_parts.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_tokens.dart';
import 'hiwiski_sheet.dart';
import 'ui_keys.dart';

/// The recurrence dialog.
///
/// It lives in `core/` because **recurring tasks go through the same component**.
/// Two dialogs for the same rule would be two places where it can
/// do different amounts — and one would always be the poorer one.
///
/// **It has to be able to do what the server and the expansion can do**:
/// interval ("every 2 weeks"), weekdays, nth weekday of the month,
/// `COUNT` and `UNTIL`. An earlier version only offered daily/weekly/monthly/yearly and gave away
/// the rest — whoever cannot enter "take out the trash every two weeks" does not enter
/// it at all and keeps it in their head. That is exactly what the app should take off
/// their hands.
///
/// Returns `null` if cancelled, and the empty string for "no recurrence" — the two are
/// not the same.
Future<String?> showRecurrenceDialog({
  required BuildContext context,
  required String? rrule,
  required DateTime start,
}) {
  return showHiwiskiSheet<String>(
    context: context,
    title: L.of(context).calRepeat,
    builder: (context) => _RecurrenceBody(rrule: rrule, start: start),
  );
}

class _RecurrenceBody extends StatefulWidget {
  const _RecurrenceBody({required this.rrule, required this.start});

  final String? rrule;
  final DateTime start;

  @override
  State<_RecurrenceBody> createState() => _RecurrenceBodyState();
}

class _RecurrenceBodyState extends State<_RecurrenceBody> {
  late bool _enabled;
  late RecurrenceSpec _spec;
  late final TextEditingController _interval;
  late final TextEditingController _count;

  /// A rule the dialog does not fully represent is **not** edited.
  ///
  /// It would come back truncated, and "every second Friday of the quarter" would
  /// silently turn into something else. Better a sentence that says so.
  late final bool _foreign;

  @override
  void initState() {
    super.initState();
    final rrule = widget.rrule;
    final given = rrule != null && rrule.isNotEmpty ? rrule : null;
    _enabled = given != null;
    _foreign = given != null && !RecurrenceSpec.understands(given);
    _spec = given != null && !_foreign
        ? RecurrenceSpec.parse(given)
        : RecurrenceSpec(weekdays: {widget.start.weekday});
    _interval = TextEditingController(text: '${_spec.interval}');
    _count = TextEditingController(text: '${_spec.count ?? 10}');
  }

  @override
  void dispose() {
    _interval.dispose();
    _count.dispose();
    super.dispose();
  }

  void _apply() {
    if (!_enabled) {
      Navigator.of(context).pop('');
      return;
    }
    Navigator.of(context).pop(_spec.toRrule());
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    if (_foreign) {
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(l.calRepeatForeign, style: context.texts.bodyMedium),
          const SizedBox(height: HiwiskiMetrics.space12),
          Text(
            (widget.rrule ?? '').replaceFirst(RruleParts.prefix, ''),
            style: context.tokens.text.monoSmall,
          ),
          const SizedBox(height: HiwiskiMetrics.space20),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: Text(l.calRepeatNone),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _enabled,
          title: Text(l.calRepeat),
          onChanged: (value) => setState(() => _enabled = value),
        ),
        if (_enabled) ...[
          const SizedBox(height: HiwiskiMetrics.space8),
          _FrequencyChips(spec: _spec, start: widget.start, onChanged: _change),
          const SizedBox(height: HiwiskiMetrics.space16),
          _IntervalRow(spec: _spec, controller: _interval, onChanged: _change),
          if (_spec.frequency == .weekly) ...[
            const SizedBox(height: HiwiskiMetrics.space16),
            _SectionLabel(l.calRepeatWeekdays),
            const SizedBox(height: HiwiskiMetrics.space8),
            _WeekdayChips(spec: _spec, onChanged: _change),
          ],
          if (_spec.frequency == .monthly) ...[
            const SizedBox(height: HiwiskiMetrics.space16),
            _MonthlyModes(spec: _spec, start: widget.start, onChanged: _change),
          ],
          const SizedBox(height: HiwiskiMetrics.space20),
          // Not `calRepeatEndNever`: a heading named exactly like the first option
          // below it reads like a statement instead of a title.
          _SectionLabel(l.calRepeatEnd),
          _EndSection(
            spec: _spec,
            count: _count,
            defaultUntil: _defaultUntil,
            onChanged: _change,
            onPickUntil: _pickUntil,
          ),
          const SizedBox(height: HiwiskiMetrics.space16),
          // What comes out in the end, in one sentence. A dialog with seven controls
          // that does not say what it is putting together is an imposition.
          Container(
            padding: const .all(HiwiskiMetrics.space12),
            decoration: BoxDecoration(
              color: context.scheme.surfaceContainerHighest,
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusChip)),
            ),
            child: Text(
              describeRecurrence(context, _spec.toRrule(), widget.start),
            ),
          ),
        ],
        SheetActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.actionCancel),
            ),
            FilledButton(onPressed: _apply, child: Text(l.actionSave)),
          ],
        ),
      ],
    );
  }

  void _change(RecurrenceSpec spec) => setState(() => _spec = spec);

  Future<void> _pickUntil() async {
    final first = DateTime(
      widget.start.year,
      widget.start.month,
      widget.start.day,
    );
    final suggested = _spec.until ?? _defaultUntil;
    final picked = await showDatePicker(
      context: context,
      // An end before the start — a foreign rule, or a start moved later — tripped the
      // picker's own check.
      initialDate: suggested.isBefore(first) ? first : suggested,
      firstDate: first,
      lastDate: DateTime(widget.start.year + 20),
    );
    if (picked != null && mounted) {
      setState(() => _spec = _spec.copyWith(end: .until, until: picked));
    }
  }

  /// Three months on, counted in days — a `Duration` of 90 days slips by an hour across
  /// a clock change.
  DateTime get _defaultUntil => addDays(widget.start, 90);

  static String _nthLabel(L l, int nth) => switch (nth) {
    2 => l.calRepeatNth2,
    3 => l.calRepeatNth3,
    4 => l.calRepeatNth4,
    -1 => l.calRepeatNthLast,
    _ => l.calRepeatNth1,
  };
}

/// Daily, weekly, monthly, yearly.
class _FrequencyChips extends StatelessWidget {
  const _FrequencyChips({
    required this.spec,
    required this.start,
    required this.onChanged,
  });

  final RecurrenceSpec spec;
  final DateTime start;
  final ValueChanged<RecurrenceSpec> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Wrap(
      spacing: HiwiskiMetrics.space8,
      children: [
        for (final entry in {
          RecurrenceFrequency.daily: l.calRepeatDaily,
          RecurrenceFrequency.weekly: l.calRepeatWeekly,
          RecurrenceFrequency.monthly: l.calRepeatMonthly,
          RecurrenceFrequency.yearly: l.calRepeatYearly,
        }.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: spec.frequency == entry.key,
            onSelected: (_) => onChanged(
              spec.copyWith(
                frequency: entry.key,
                // When switching to "weekly" the start day is the only sensible
                // default; a rule without BYDAY would take it anyway.
                weekdays: entry.key == .weekly && spec.weekdays.isEmpty
                    ? {start.weekday}
                    : spec.weekdays,
              ),
            ),
          ),
      ],
    );
  }
}

/// "Every [n] weeks".
class _IntervalRow extends StatelessWidget {
  const _IntervalRow({
    required this.spec,
    required this.controller,
    required this.onChanged,
  });

  final RecurrenceSpec spec;
  final TextEditingController controller;
  final ValueChanged<RecurrenceSpec> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final unit = switch (spec.frequency) {
      .daily => l.calRepeatUnitDay,
      .weekly => l.calRepeatUnitWeek,
      .monthly => l.calRepeatUnitMonth,
      .yearly => l.calRepeatUnitYear,
    };
    // "Every [2] weeks"; with large text the unit moves to the next line.
    return Wrap(
      spacing: HiwiskiMetrics.space12,
      crossAxisAlignment: .center,
      children: [
        Text(l.calRepeatEvery),
        SizedBox(
          width: HiwiskiMetrics.shortFieldWidth,
          child: TextField(
            key: CoreKeys.recurrenceInterval,
            controller: controller,
            keyboardType: .number,
            textAlign: .center,
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null && parsed > 0) {
                onChanged(spec.copyWith(interval: parsed));
              }
            },
          ),
        ),
        Text(unit),
      ],
    );
  }
}

/// The weekdays of a weekly rule.
class _WeekdayChips extends StatelessWidget {
  const _WeekdayChips({required this.spec, required this.onChanged});

  final RecurrenceSpec spec;
  final ValueChanged<RecurrenceSpec> onChanged;

  @override
  Widget build(BuildContext context) {
    final symbols = DateFormat.EEEE(Localizations.localeOf(context).toString())
        .dateSymbols;
    return Wrap(
      spacing: HiwiskiMetrics.space6,
      children: [
        for (var day = DateTime.monday; day <= DateTime.sunday; day++)
          FilterChip(
            label: Text(symbols.SHORTWEEKDAYS[day % 7]),
            selected: spec.weekdays.contains(day),
            onSelected: (selected) {
              final next = Set<int>.of(spec.weekdays);
              if (selected) {
                next.add(day);
              } else {
                next.remove(day);
              }
              // No day selected is no rule: the expansion would then take the
              // start day, and the dialog would show something other than what
              // applies.
              if (next.isNotEmpty) onChanged(spec.copyWith(weekdays: next));
            },
          ),
      ],
    );
  }
}

/// A monthly rule: on the day of the month, or on its nth weekday.
class _MonthlyModes extends StatelessWidget {
  const _MonthlyModes({
    required this.spec,
    required this.start,
    required this.onChanged,
  });

  final RecurrenceSpec spec;
  final DateTime start;
  final ValueChanged<RecurrenceSpec> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final symbols = DateFormat.EEEE(Localizations.localeOf(context).toString())
        .dateSymbols;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        RadioGroup<MonthlyMode>(
          groupValue: spec.monthlyMode,
          onChanged: (value) => onChanged(
            spec.copyWith(
              monthlyMode: value,
              // The start event's nth weekday is the default that surprises
              // nobody.
              nth: RecurrenceSpec.nthOfMonth(start),
              nthWeekday: start.weekday,
            ),
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              RadioListTile<MonthlyMode>(
                contentPadding: EdgeInsets.zero,
                value: .dayOfMonth,
                title: Text(l.calRepeatMonthlyDay(start.day)),
              ),
              RadioListTile<MonthlyMode>(
                contentPadding: EdgeInsets.zero,
                value: .nthWeekday,
                title: Text(
                  l.calRepeatMonthlyWeekday(
                    _RecurrenceBodyState._nthLabel(l, spec.nth),
                    symbols.WEEKDAYS[spec.nthWeekday % 7],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (spec.monthlyMode == .nthWeekday)
          Padding(
            padding: const .only(left: HiwiskiMetrics.space16),
            child: Wrap(
              spacing: HiwiskiMetrics.space6,
              children: [
                for (final value in const [1, 2, 3, 4, -1])
                  ChoiceChip(
                    label: Text(_RecurrenceBodyState._nthLabel(l, value)),
                    selected: spec.nth == value,
                    onSelected: (_) => onChanged(spec.copyWith(nth: value)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// How the series ends: never, after a count, or on a date.
///
/// One `RadioGroup` around the three rows, instead of `groupValue` per row.
///
/// The second and third rows carry an input field: whoever types there also means
/// the choice. That is why every field also sets its row on change — otherwise you
/// type in a number that applies nowhere.
class _EndSection extends StatelessWidget {
  const _EndSection({
    required this.spec,
    required this.count,
    required this.defaultUntil,
    required this.onChanged,
    required this.onPickUntil,
  });

  final RecurrenceSpec spec;
  final TextEditingController count;
  final DateTime defaultUntil;
  final ValueChanged<RecurrenceSpec> onChanged;
  final VoidCallback onPickUntil;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return RadioGroup<RecurrenceEnd>(
      groupValue: spec.end,
      onChanged: (value) => onChanged(
        spec.copyWith(
          end: value,
          // The same check as the field's own: "0" there was ignored, but choosing
          // the row took it anyway and saved `COUNT=0` — a series without a single
          // event.
          count: value == .count
              ? switch (int.tryParse(count.text)) {
                  final int n when n > 0 => n,
                  _ => 10,
                }
              : spec.count,
          until: value == .until ? (spec.until ?? defaultUntil) : spec.until,
        ),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          RadioListTile<RecurrenceEnd>(
            contentPadding: EdgeInsets.zero,
            value: .never,
            title: Text(l.calRepeatEndNever),
          ),
          RadioListTile<RecurrenceEnd>(
            contentPadding: EdgeInsets.zero,
            value: .count,
            // Wraps like the interval above: with large text the words go to the
            // next line instead of past the edge.
            title: Wrap(
              spacing: HiwiskiMetrics.space12,
              crossAxisAlignment: .center,
              children: [
                Text(l.calRepeatEndAfter),
                SizedBox(
                  width: HiwiskiMetrics.shortFieldWidth,
                  child: TextField(
                    key: CoreKeys.recurrenceCount,
                    controller: count,
                    keyboardType: .number,
                    textAlign: .center,
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        onChanged(spec.copyWith(end: .count, count: parsed));
                      }
                    },
                  ),
                ),
                Text(l.calRepeatTimes),
              ],
            ),
          ),
          RadioListTile<RecurrenceEnd>(
            contentPadding: EdgeInsets.zero,
            value: .until,
            title: Wrap(
              spacing: HiwiskiMetrics.space12,
              crossAxisAlignment: .center,
              children: [
                Text(l.calRepeatEndOn),
                TextButton(
                  onPressed: onPickUntil,
                  child: Text(switch (spec.until) {
                    null => '—',
                    final until => DateFormat.yMMMd(
                      Localizations.localeOf(context).toString(),
                    ).format(until),
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: context.tokens.text.sectionLabel);
}

/// The rule in one sentence, for the row and the info bar.
///
/// An `RRULE` is meant for the server, not for the kitchen table. What cannot be put
/// into words is shown as raw text — better honestly ugly than wrong.
String describeRecurrence(BuildContext context, String? rrule, DateTime start) {
  final l = L.of(context);
  if (rrule == null || rrule.isEmpty) return l.calRepeatNone;
  if (!RecurrenceSpec.understands(rrule)) {
    return rrule.replaceFirst(RruleParts.prefix, '');
  }

  final spec = RecurrenceSpec.parse(rrule);
  final locale = Localizations.localeOf(context).toString();
  final symbols = DateFormat.EEEE(locale).dateSymbols;
  final buffer = StringBuffer();

  if (spec.interval == 1) {
    buffer.write(switch (spec.frequency) {
      .daily => l.calRepeatDaily,
      .weekly => l.calRepeatWeekly,
      .monthly => l.calRepeatMonthly,
      .yearly => l.calRepeatYearly,
    });
  } else {
    buffer.write('${l.calRepeatEvery} ${spec.interval} ');
    buffer.write(switch (spec.frequency) {
      .daily => l.calRepeatUnitDay,
      .weekly => l.calRepeatUnitWeek,
      .monthly => l.calRepeatUnitMonth,
      .yearly => l.calRepeatUnitYear,
    });
  }

  if (spec.frequency == .weekly && spec.weekdays.isNotEmpty) {
    final ordered = spec.weekdays.toList()..sort();
    buffer.write(
      ', ${ordered.map((day) => symbols.SHORTWEEKDAYS[day % 7]).join(', ')}',
    );
  }

  if (spec.frequency == .monthly && spec.monthlyMode == .nthWeekday) {
    buffer.write(
      ', ${l.calRepeatMonthlyWeekday(switch (spec.nth) {
        2 => l.calRepeatNth2,
        3 => l.calRepeatNth3,
        4 => l.calRepeatNth4,
        -1 => l.calRepeatNthLast,
        _ => l.calRepeatNth1,
      }, symbols.WEEKDAYS[spec.nthWeekday % 7])}',
    );
  }

  switch (spec.end) {
    case .never:
      break;
    case .count:
      buffer.write(
        ', ${l.calRepeatEndAfter} ${spec.count} ${l.calRepeatTimes}',
      );
    case .until:
      if (spec.until case final until?) {
        buffer.write(
          ', ${l.calRepeatEndOn} ${DateFormat.yMMMd(locale).format(until)}',
        );
      }
  }

  return buffer.toString();
}
