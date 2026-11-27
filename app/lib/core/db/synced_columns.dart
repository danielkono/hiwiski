import 'package:drift/drift.dart';

import '../common/wire.dart';
import 'hiwiski_database.dart';

/// The columns a synced item's fields are kept in, by their names on the wire.
///
/// One map per table, which the sync codec and the repository both read and write
/// through: a field is mapped to its column once, and all that goes over every field
/// of an item — reading its row, writing a change, bringing it back, storing what
/// arrives — goes over this map. A field without its column here is neither stored
/// nor sent; `test/pinboard_fields_test.dart` names it.
final class SyncedColumns<D> {
  const SyncedColumns(this.byField);

  final Map<String, GeneratedColumn<Object>> byField;

  /// The fields of [row], each as its column holds it.
  Map<String, Object?> fieldsOf(Insertable<D> row) {
    final values = row.toColumns(false);
    return {
      for (final MapEntry(key: field, value: column) in byField.entries)
        field: switch (values[column.name]) {
          Variable(:final value) => value,
          _ => null,
        },
    };
  }

  /// [fields] as values for their columns — those this table has. A field a column
  /// cannot keep empty is left out when it comes empty: the row keeps what it has,
  /// a new one its column's default.
  Map<String, Expression<Object>> valuesOf(Map<String, Object?> fields) => {
    for (final MapEntry(key: field, :value) in fields.entries)
      if (byField[field] case final column?)
        if (value != null || column.$nullable)
          column.name: _variableOf(column, value),
  };

  /// A row of [values] for an item: a change written, or a new or returned item.
  Insertable<D> rowOf(Map<String, Expression<Object>> values) =>
      RawValuesInsertable(values);

  /// [value] as [column] keeps it: a number from JSON may come as either kind.
  static Expression<Object> _variableOf(
    GeneratedColumn<Object> column,
    Object? value,
  ) => switch (column.type) {
    DriftSqlType.int => Variable<int>(switch (value) {
      final num number => number.round(),
      _ => null,
    }),
    DriftSqlType.double => Variable<double>(switch (value) {
      final num number => number.toDouble(),
      _ => null,
    }),
    DriftSqlType.string => Variable<String>(value?.toString()),
    _ => Variable<Object>(value),
  };
}

/// An element of a pinboard: its fields and their columns. A new field gets its
/// line here, next to its column in `tables.dart`.
SyncedColumns<PinboardNodeRow> pinboardNodeColumns(HiwiskiDatabase db) {
  final table = db.pinboardNodes;
  return SyncedColumns({
    WireFields.kind: table.kind,
    WireFields.x: table.x,
    WireFields.y: table.y,
    WireFields.width: table.width,
    WireFields.height: table.height,
    WireFields.layer: table.layer,
    WireFields.text: table.body,
    WireFields.target: table.target,
    WireFields.linkView: table.linkView,
    WireFields.color: table.color,
    WireFields.shape: table.shape,
    WireFields.textSize: table.textSize,
    WireFields.textColor: table.textColor,
    WireFields.points: table.points,
    WireFields.strokeWidth: table.strokeWidth,
    WireFields.rotation: table.rotation,
    WireFields.textAlign: table.textAlign,
    WireFields.textFlow: table.textFlow,
    WireFields.calendars: table.calendars,
    WireFields.week: table.week,
  });
}

/// A connection of a pinboard: its fields and their columns.
SyncedColumns<PinboardEdgeRow> pinboardEdgeColumns(HiwiskiDatabase db) {
  final table = db.pinboardEdges;
  return SyncedColumns({
    WireFields.fromId: table.fromId,
    WireFields.toId: table.toId,
    WireFields.text: table.body,
    WireFields.color: table.color,
    WireFields.strokeWidth: table.strokeWidth,
    WireFields.line: table.line,
    WireFields.arrows: table.arrows,
  });
}
