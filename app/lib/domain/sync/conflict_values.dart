import 'dart:convert';

import '../../core/common/wire.dart';
import '../todo/kanban.dart';

/// A conflict's value as a person reads it — not as it travels.
///
/// The conflict sheet showed what the wire carries: a board's columns as JSON with
/// their ids, a card's column as a bare UUID, a box as `DONE`. Nobody can choose
/// between two UUIDs. These are the kinds of value that need more than a join.
sealed class ConflictValue {
  const ConflictValue();
}

/// Plain text — everything without a meaning of its own.
final class TextValue extends ConflictValue {
  const TextValue(this.text);

  final String text;
}

/// A board's columns, in their order.
final class ColumnsValue extends ConflictValue {
  const ColumnsValue(this.columns);

  final List<KanbanColumn> columns;
}

/// The column a card stands in; `name` is `null` when no column of the board — then
/// or now — has that id any more.
final class ColumnValue extends ConflictValue {
  const ColumnValue(this.name);

  final String? name;
}

/// A box ticked or not.
final class StatusValue extends ConflictValue {
  const StatusValue({required this.done});

  final bool done;
}

/// Reads [json] — the stored value of [field] — as a [ConflictValue]. [board] are the
/// columns a card's `columnId` is looked up in: the board's as they are now, and those
/// any side of the conflict carries.
ConflictValue readConflictValue(
  String field,
  String? json, {
  List<KanbanColumn> board = const [],
}) {
  final Object? value = _decode(json);
  switch (field) {
    case WireFields.columns:
      return ColumnsValue(
        parseColumns(value is String ? value : jsonEncode(value)),
      );
    case WireFields.columnId:
      if (value == null) return const TextValue('');
      return ColumnValue(
        board
            .where((column) => column.id == value.toString())
            .firstOrNull
            ?.name,
      );
    case WireFields.status:
      return StatusValue(done: value == TodoStatuses.done);
  }
  return TextValue(switch (value) {
    null => '',
    final List<dynamic> list => list.join(', '),
    final Object other => other.toString(),
  });
}

Object? _decode(String? json) {
  if (json == null) return null;
  try {
    return jsonDecode(json);
  } on FormatException {
    return json;
  }
}
