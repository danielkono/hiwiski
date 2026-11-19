import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../../core/api/generated/export.dart';

/// One row of an item's history: a change, the version a change left, or both.
@immutable
class HistoryRow {
  /// A change — with the version it left, if it left one.
  HistoryRow.change(HistoryEntry this.entry, {this.revision}) : at = entry.at;

  /// A version without its change: the log no longer holds the save, or it is a
  /// conflict version (the save that lost was never written).
  HistoryRow.version(Revision this.revision)
    : entry = null,
      at = revision.createdAt;

  final HistoryEntry? entry;

  /// The version this row opens.
  final Revision? revision;

  final DateTime at;
}

/// A page's changes and versions as **one** list, newest first.
///
/// A change that left a version is one row that opens it. Versions without a change
/// still get a row of their own: they outlive the log (versions are kept, the log only
/// for its retention period), and a conflict version has no change at all — leaving
/// them out would make them impossible to restore.
List<HistoryRow> historyRows(
  List<HistoryEntry> entries,
  List<Revision> revisions,
) {
  final bySave = {
    for (final revision in revisions) ?revision.changeSeq: revision,
  };
  final rows = [
    for (final entry in entries)
      HistoryRow.change(entry, revision: bySave.remove(entry.seq)),
  ];
  final linked = {for (final row in rows) ?row.revision?.id};
  rows.addAll([
    for (final revision in revisions)
      if (!linked.contains(revision.id)) HistoryRow.version(revision),
  ]);
  // Stable: a change and a version at the same moment keep the order above.
  mergeSort(rows, compare: (a, b) => b.at.compareTo(a.at));
  return rows;
}
