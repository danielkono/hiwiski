import 'package:flutter/material.dart';

import '../../../components/rich_text/view/markdown_text_controller.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/item_navigation.dart';
import '../../../core/routing/routes.dart';
import '../../../core/ui/archive_ui.dart';
import '../../../core/ui/edit_actions.dart';
import '../../../core/ui/page_header.dart';
import '../../../domain/todo/todo_items.dart';

// The parts the three list screens — checklist, shopping, Kanban — share. Passive:
// what they show and what they do comes from the screen's ViewModel.

/// Stands where the number will: created offline, a list has none yet.
const _noKey = '—';

/// The header of a list: name, number and open count, back, the archive mark and
/// "Edit".
class ListHeader extends PageHeader {
  ListHeader(
    BuildContext context, {
    super.key,
    required TodoList? list,
    required int open,
    required bool writable,
    required VoidCallback onEdit,
    bool editing = false,
    VoidCallback? onSave,
    VoidCallback? onCancel,
  }) : super(
         title: list?.name ?? '',
         // The item line: the citable number and the context — "LST-3 · 5 open".
         // Before its first sync a list has no number yet, and the dash says so.
         entityKey: list == null ? null : (list.entityKey ?? _noKey),
         detail: L.of(context).widgetOpenCount(open),
         onBack: () => goBack(context, () => const TodoRoute().go(context)),
         trailing: [
           if (list?.archivedAt != null) const ArchivedChip(),
           // "Edit", and while the fields are open on the page "Cancel" and "Save"
           // in its place — as on every item.
           if (writable && list != null)
             EditActions(
               editing: editing,
               onEdit: onEdit,
               onSave: onSave,
               onCancel: onCancel ?? () {},
               // Greyed out while images are still being added to the description.
               saveBlocked: MarkdownTextController.addingImagesAnywhere,
             ),
         ],
       );
}
