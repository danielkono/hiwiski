import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/common/date_patterns.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/recurrence_dialog.dart';
import '../../../domain/tags/tag.dart';
import '../../../domain/todo/todo_items.dart';

/// "Tue, 29.09. · Ben · every week" — due date, assignment, repeat.
String todoMeta(BuildContext context, Todo todo, Map<String, Member> members) {
  final l = L.of(context);
  final locale = Localizations.localeOf(context).toString();
  final parts = <String>[];
  if (todo.dueDate case final due?) {
    final today = clock.now();
    final isToday =
        due.year == today.year &&
        due.month == today.month &&
        due.day == today.day;
    parts.add(
      isToday
          ? l.todoToday
          : DateFormat(DatePatterns.weekdayDayMonth, locale).format(due),
    );
  }
  final ids = tagIdsOf(todo.assignees);
  if (ids.isNotEmpty) {
    parts.add(
      [for (final id in ids) members[id]?.displayName ?? '—'].join(', '),
    );
  }
  if ((todo.rrule ?? '').isNotEmpty) {
    parts.add(
      describeRecurrence(context, todo.rrule, todo.dueDate ?? clock.now()),
    );
  }
  return parts.join(' · ');
}
