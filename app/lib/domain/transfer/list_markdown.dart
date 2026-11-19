/// A list as one Markdown file: its tasks as a task list anyone can read, tick and
/// extend in another editor.
///
/// ```markdown
/// ---
/// type: todo_list
/// name: "Weekly shopping"
/// kind: SHOPPING
/// ---
///
/// The list's description.
///
/// - [ ] Milk
///   - amount: 2
///   - unit: l
/// - [x] Bread
///
///   A task's description, indented below it.
/// ```
///
/// A board has one `## Column` heading per column, its tasks below it. What a task
/// has beyond its title stands right below its line as `- field: value`, with the
/// names the database uses.
library;

import '../../core/common/wire.dart';
import 'front_matter.dart';
import 'transfer_models.dart';

/// [list] as the text of its file.
String listMarkdown(TransferList list) {
  final board = list.kind == ListKinds.kanban && list.columns.isNotEmpty;
  final out = StringBuffer()
    ..write(
      writeFrontMatter({
        TransferFields.type: TransferTypes.todoList,
        TransferFields.name: list.name,
        TransferFields.kind: list.kind,
        TransferFields.colorToken: list.colorToken,
        if (list.tags.isNotEmpty) TransferFields.tags: list.tags,
        if (board)
          TransferFields.columns: [
            for (final column in list.columns)
              {
                TransferFields.columnName: column.name,
                TransferFields.columnColorToken: column.colorToken,
                TransferFields.columnDone: column.done,
              },
          ],
      }),
    );
  if (list.description?.trim() case final description? when description != '') {
    out
      ..writeln()
      ..writeln(description);
  }
  if (!board) {
    out.writeln();
    for (final task in list.tasks) {
      _writeTask(out, task);
    }
    return out.toString();
  }
  for (final (index, column) in list.columns.indexed) {
    out.write('\n$_columnHeading${column.name}\n\n');
    for (final task in list.tasks) {
      if (task.column == index) _writeTask(out, task);
    }
  }
  return out.toString();
}

void _writeTask(StringBuffer out, TransferTask task) {
  out.writeln('${task.done ? _doneBox : _openBox}${_oneLine(task.title)}');
  void field(String name, Object? value) {
    if (value != null) out.writeln('$_indent- $name: $value');
  }

  field(TransferFields.dueDate, switch (task.dueDate) {
    final date? => _date(date),
    null => null,
  });
  field(TransferFields.dueTime, task.dueTime);
  field(TransferFields.rrule, task.rrule);
  field(TransferFields.amount, switch (task.amount) {
    final amount? when amount == amount.roundToDouble() => amount.toInt(),
    final amount => amount,
  });
  field(TransferFields.unit, task.unit);
  if (task.tags.isNotEmpty) {
    field(TransferFields.tags, task.tags.join(_tagSeparator));
  }
  if (task.description?.trim() case final description? when description != '') {
    out.writeln();
    for (final line in description.split('\n')) {
      out.writeln(line.isEmpty ? '' : '$_indent$line');
    }
    out.writeln();
  }
}

/// A list read from [markdown] — a file this app wrote or a task list written by
/// hand. [fallbackName] names a list whose file does not: its file name.
///
/// Forgiving on purpose: a list item without a box is an open task, and text that is
/// neither a task nor part of one joins the list's description instead of being
/// dropped.
TransferList parseList(String markdown, {required String fallbackName}) {
  final (:fields, :body) = splitFrontMatter(markdown);
  final columns = _columns(fields[TransferFields.columns]);
  final kind = switch (fields[TransferFields.kind]) {
    ListKinds.shopping => ListKinds.shopping,
    // A board needs its columns; without them the tasks are a plain list.
    ListKinds.kanban when columns.isNotEmpty => ListKinds.kanban,
    _ => ListKinds.standard,
  };
  final board = kind == ListKinds.kanban;

  final description = <String>[];
  final tasks = <_TaskDraft>[];
  _TaskDraft? task;
  int? column;
  for (final line in body.split('\n')) {
    if (_taskLine.firstMatch(line) case final match?) {
      task = _TaskDraft(
        title: (match.group(_titleGroup) ?? _none).trim(),
        // No box at all is an open task.
        done: (match.group(_boxGroup) ?? '').trim().isNotEmpty,
        column: column,
      );
      tasks.add(task);
    } else if (task != null && (line.trim().isEmpty || _indented(line))) {
      task.take(_indented(line) ? line.substring(_indentOf(line)) : '');
    } else if (board && line.startsWith(_columnHeading)) {
      final name = line.substring(_columnHeading.length).trim();
      final index = columns.indexWhere((column) => column.name == name);
      column = index < 0 ? null : index;
      task = null;
    } else {
      task = null;
      description.add(line);
    }
  }

  final name = fields[TransferFields.name];
  final color = fields[TransferFields.colorToken];
  return TransferList(
    name: name is String && name.trim().isNotEmpty ? name.trim() : fallbackName,
    kind: kind,
    description: _text(description),
    colorToken: color is String ? color : null,
    tags: stringList(fields[TransferFields.tags]),
    columns: board ? columns : const [],
    tasks: [for (final draft in tasks) draft.build()],
  );
}

/// Whether [markdown] holds at least one task — what makes a file without front
/// matter a list.
bool hasTasks(String markdown) =>
    splitFrontMatter(markdown).body.split('\n').any(_taskLine.hasMatch);

List<TransferColumn> _columns(Object? value) {
  if (value is! List<Object?>) return const [];
  final columns = [
    for (final element in value)
      if (element case {TransferFields.columnName: final String name}
          when name.trim().isNotEmpty)
        TransferColumn(
          name: name.trim(),
          colorToken: switch (element[TransferFields.columnColorToken]) {
            final String token => token,
            _ => ColorTokens.blue,
          },
          done: element[TransferFields.columnDone] == true,
        ),
  ];
  // What the server accepts as a board; anything else imports as a plain list.
  final valid =
      columns.length >= _minColumns &&
      columns.length <= _maxColumns &&
      columns.any((column) => column.done) &&
      columns.any((column) => !column.done);
  return valid ? columns : const [];
}

/// A task while its lines are read.
class _TaskDraft {
  _TaskDraft({required this.title, required this.done, required this.column});

  final String title;
  final bool done;
  final int? column;
  final _fields = <String, String>{};
  final _description = <String>[];

  /// Fields stand right below the task's line; the first other line starts the
  /// description, and from there everything is text — also a line that looks like a
  /// field.
  bool _inDescription = false;

  void take(String line) {
    if (!_inDescription) {
      if (_fieldLine.firstMatch(line) case final match?) {
        _fields[match.group(_fieldNameGroup) ?? _none] =
            (match.group(_fieldValueGroup) ?? _none).trim();
        return;
      }
      if (line.trim().isEmpty) {
        _inDescription = true;
        return;
      }
      _inDescription = true;
    }
    _description.add(line);
  }

  TransferTask build() => .new(
    title: title,
    done: done,
    column: column,
    description: _text(_description),
    dueDate: switch (_fields[TransferFields.dueDate]) {
      final value? when _dateOnly.hasMatch(value) => DateTime.tryParse(value),
      _ => null,
    },
    dueTime: switch (_fields[TransferFields.dueTime]) {
      final value? when _timeOnly.hasMatch(value) => value,
      _ => null,
    },
    rrule: _filled(_fields[TransferFields.rrule]),
    amount: switch (_fields[TransferFields.amount]) {
      // "1,5" is how half of Europe writes it.
      final value? => double.tryParse(value.replaceAll(',', '.')),
      null => null,
    },
    unit: _filled(_fields[TransferFields.unit]),
    tags: [
      for (final tag in (_fields[TransferFields.tags] ?? '').split(','))
        if (tag.trim().isNotEmpty) tag.trim(),
    ],
  );
}

String? _filled(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

/// Lines as one text, without the blank lines around it; `null` when nothing is left.
String? _text(List<String> lines) => _filled(lines.join('\n'));

String _oneLine(String text) => text.replaceAll(_lineBreaks, ' ').trim();

String _date(DateTime date) =>
    '${date.year.toString().padLeft(_yearDigits, _zero)}-'
    '${date.month.toString().padLeft(2, _zero)}-'
    '${date.day.toString().padLeft(2, _zero)}';

bool _indented(String line) => _indentOf(line) > 0;

/// How much of [line] is the indent that puts it below a task: two spaces or a tab.
int _indentOf(String line) => switch (line) {
  _ when line.startsWith(_indent) => _indent.length,
  _ when line.startsWith(_tab) => _tab.length,
  _ => 0,
};

const _openBox = '- [ ] ';
const _doneBox = '- [x] ';
const _columnHeading = '## ';
const _indent = '  ';
const _tab = '\t';
const _tagSeparator = ', ';
const _zero = '0';
const _yearDigits = 4;

// The board's limits, as `domain/todo/kanban.dart` and the server have them.
const _minColumns = 2;
const _maxColumns = 8;

const _boxGroup = 1;
const _titleGroup = 2;

/// A list item at the start of a line, with or without a box.
final _taskLine = RegExp(r'^[-*+] (?:\[([ xX])\] )?(\S.*)$');

const _fieldNameGroup = 1;
const _fieldValueGroup = 2;
final _fieldLine = RegExp(
  '^- (${[TransferFields.dueDate, TransferFields.dueTime, TransferFields.rrule, TransferFields.amount, TransferFields.unit, TransferFields.tags].join('|')}):(.*)\$',
);
final _dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _timeOnly = RegExp(r'^\d{2}:\d{2}(:\d{2})?$');
final _lineBreaks = RegExp(r'[\r\n]+');

/// A group that did not take part in a match.
const _none = '';
