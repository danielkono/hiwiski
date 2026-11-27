import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/components/history/view/history_section.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations_de.dart';
import 'package:hiwiski/core/ui/history_field_label.dart';
import 'package:hiwiski/domain/common/item_ref.dart';

/// **A history row says what happened**:
/// which way status and archive went, each field by the name the form gives it, and
/// "created" only for the creation.
void main() {
  final de = LDe();
  final at = DateTime(2026, 10, 26, 9);

  HistoryEntry entry(
    List<String> fields, [
    TodoStatus? status,
    bool? archived,
  ]) => .new(
    seq: 2,
    at: at,
    op: .upsert,
    fields: fields,
    status: status,
    archived: archived,
  );

  test('checking off and opening again read differently', () {
    expect(historyChange(de, entry(['status'], .done)), equals('abgehakt'));
    expect(
      historyChange(de, entry(['status'], .open)),
      equals('wieder geöffnet'),
    );
  });

  test('a card says which column it went to', () {
    HistoryEntry moved(
      List<String> fields,
      String? column, [
      TodoStatus? status,
    ]) => entry(fields, status).copyWith(column: column);
    expect(
      historyChange(de, moved(['columnId', 'position'], 'In Arbeit')),
      equals('verschoben nach „In Arbeit“'),
    );
    expect(
      historyChange(de, moved(['columnId', 'status'], 'Erledigt', .done)),
      equals('abgehakt, verschoben nach „Erledigt“'),
    );
    // The column is gone since: the field name, as before.
    expect(
      historyChange(de, moved(['columnId'], null)),
      equals('geändert: Spalte'),
    );
  });

  test('other fields of the same change follow the direction', () {
    expect(
      historyChange(de, entry(['columnId', 'status'], .done)),
      equals('abgehakt, geändert: Spalte'),
    );
  });

  test('without the value (an older server) the field name stays neutral', () {
    expect(historyChange(de, entry(['status'])), equals('geändert: Status'));
    expect(
      historyChange(de, entry(['status'], .$unknown)),
      equals('geändert: Status'),
    );
  });

  test('a status sent along with an untouched field is no status change', () {
    expect(
      historyChange(de, entry(['dueDate'], .done)),
      equals('geändert: Fällig'),
    );
  });

  test('archiving and restoring read differently', () {
    expect(
      historyChange(de, entry(['archivedAt', 'archivedBy'], null, true)),
      equals('archiviert'),
    );
    expect(
      historyChange(de, entry(['archivedAt', 'archivedBy'], null, false)),
      equals('wiederhergestellt'),
    );
    expect(
      historyChange(de, entry(['archivedAt', 'archivedBy'])),
      equals('geändert: Archiv'),
    );
  });

  test('every field has the name the form gives it', () {
    expect(historyFieldLabel(de, 'endsAt'), equals('Ende'));
    expect(historyFieldLabel(de, 'localEnd'), equals('Ende'));
    expect(historyFieldLabel(de, 'startsAt'), equals('Beginn'));
    expect(historyFieldLabel(de, 'tags'), equals('Tags'));
    expect(historyFieldLabel(de, 'kind'), equals('Art'));
    expect(historyFieldLabel(de, 'imageId'), equals('Bild'));
    expect(historyFieldLabel(de, 'exceptions'), equals('Einzelne Termine'));
    // A pinboard's: an element turned, a connection drawn another way.
    expect(historyFieldLabel(de, 'rotation'), equals('Drehung'));
    expect(historyFieldLabel(de, 'line'), equals('Linienart'));
    expect(historyFieldLabel(de, 'arrows'), equals('Linienart'));
  });

  group('created', () {
    // 2026-07-01 as a UUIDv7.
    const youngId = '019f1af9-b400-7000-8000-000000000000';
    // 2026-01-01 — older than the history reaches back.
    const oldId = '019b76da-a800-7000-8000-000000000000';
    final reachesBack = DateTime(2026, 4, 1);
    HistoryEntry at(int seq, DateTime when) =>
        .new(seq: seq, at: when, op: .upsert, fields: const ['title']);
    final newest = at(2, DateTime(2026, 10, 20));
    final oldest = at(1, DateTime(2026, 7, 1));

    test('the oldest entry of a young item is its creation', () {
      expect(
        isCreationEntry(
          oldest,
          [newest, oldest],
          reachesBack,
          const ItemRef.todo(youngId),
        ),
        isTrue,
      );
    });

    test('an item older than the history has no creation in it', () {
      // Retention deleted the creation; what is left is merely the oldest change.
      expect(
        isCreationEntry(
          oldest,
          [newest, oldest],
          reachesBack,
          const ItemRef.todo(oldId),
        ),
        isFalse,
      );
    });

    test("in a list's history each task's oldest entry is its creation", () {
      // The list is old; a young task in it was created within the history.
      final task = HistoryEntry(
        seq: 3,
        at: DateTime(2026, 7, 1),
        op: .upsert,
        fields: const ['title'],
        entryId: youngId,
      );
      final taskChange = task.copyWith(seq: 4, at: DateTime(2026, 10, 21));
      final entries = [taskChange, task, newest, oldest];
      const list = ItemRef.todoList(oldId);
      expect(isCreationEntry(task, entries, reachesBack, list), isTrue);
      expect(isCreationEntry(taskChange, entries, reachesBack, list), isFalse);
      expect(isCreationEntry(oldest, entries, reachesBack, list), isFalse);
    });
  });
}
