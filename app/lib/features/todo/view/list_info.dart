import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../components/export/view/info_export_button.dart';
import '../../../components/item_info/view/item_info.dart';
import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/ui/archive_ui.dart';
import '../../../core/ui/info_archive_button.dart';
import '../../../core/ui/info_delete_section.dart';
import '../../../core/ui/info_property.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/todo/kanban.dart';
import '../../../domain/todo/todo_items.dart';

/// A list's info area: kind and entries, what the screen adds, then everything every
/// item has (`ItemInfo`), archive and delete last.
class ListInfo extends StatelessWidget {
  const ListInfo({
    super.key,
    required this.list,
    required this.entries,
    required this.open,
    required this.writable,
    required this.mayChange,
    required this.mayDelete,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    this.extra = const [],
  });

  final TodoList list;
  final int entries;
  final int open;
  final bool writable;

  /// Archive and delete stay with whoever may write — archived or not.
  final bool mayChange;

  /// Delete is the owner's alone.
  final bool mayDelete;
  final AsyncCallback onArchive;
  final AsyncCallback onRestore;
  final AsyncCallback onDelete;

  /// The rows only this kind of list has: its columns, "Edit categories" …
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final archived = list.archivedAt != null;
    return ItemInfo(
      item: ItemRef.todoList(list.id),
      editable: writable,
      properties: [
        InfoProperty(
          label: l.listKind,
          value: switch (list.kind) {
            ListKinds.shopping => l.todoKindShopping,
            kindKanban => l.todoKindKanban,
            _ => l.todoKindStandard,
          },
        ),
        InfoProperty(
          label: l.listEntries,
          value: l.listEntriesValue(entries, open),
        ),
        ...extra,
      ],
      actions: [
        // Export is everyone's who can read the list; archive and delete follow it
        // in the same row.
        if (mayDelete)
          InfoDeleteSection(
            besides: [
              InfoExportButton(item: ItemRef.todoList(list.id)),
              if (!archived)
                _ArchiveListButton(onArchive: onArchive, onRestore: onRestore),
            ],
            label: l.todoDeleteList,
            confirmTitle: l.todoDeleteListConfirm,
            onDelete: () async {
              await onDelete();
              if (context.mounted) const TodoRoute().go(context);
            },
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: HiwiskiMetrics.space16,
              crossAxisAlignment: .center,
              children: [
                InfoExportButton(item: ItemRef.todoList(list.id)),
                if (mayChange && !archived)
                  _ArchiveListButton(
                    onArchive: onArchive,
                    onRestore: onRestore,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ArchiveListButton extends StatelessWidget {
  const _ArchiveListButton({required this.onArchive, required this.onRestore});

  final AsyncCallback onArchive;
  final AsyncCallback onRestore;

  @override
  Widget build(BuildContext context) => InfoArchiveButton(
    label: L.of(context).todoArchiveList,
    onArchive: () async {
      await onArchive();
      if (!context.mounted) return;
      // Back to the overview, where the list no longer is — "Undo" brings it back.
      showArchivedSnackBar(context, onUndo: onRestore);
      const TodoRoute().go(context);
    },
  );
}
