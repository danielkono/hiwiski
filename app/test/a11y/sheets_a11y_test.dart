import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/components/export/view/export_sheet.dart';
import 'package:hiwiski/components/import/view/import_sheet.dart';
import 'package:hiwiski/domain/transfer/transfer_models.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/components/assignees/view/assignees.dart';
import 'package:hiwiski/components/links/view/link_picker.dart';
import 'package:hiwiski/components/links/view/link_preview.dart';
import 'package:hiwiski/components/sharing/view/share_sheet.dart';
import 'package:hiwiski/components/sync_banner/view/conflict_sheet.dart';
import 'package:hiwiski/components/sync_banner/view/stuck_sheet.dart';
import 'package:hiwiski/components/tags/view/tag_widgets.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/ui/recurrence_dialog.dart';
import 'package:hiwiski/domain/common/item_ref.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/domain/sync/sync_items.dart';
import 'package:hiwiski/domain/wiki/wiki_models.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:hiwiski/features/account/my_account/view/change_password_sheet.dart';
import 'package:hiwiski/features/admin/trash/view/restore_target_sheet.dart';
import 'package:hiwiski/features/board/widget_config/view/widget_config_sheet.dart';
import 'package:hiwiski/features/calendar/event_sheet/view/event_sheet.dart';
import 'package:hiwiski/features/calendar/manage_calendars/view/calendar_sheets.dart';
import 'package:hiwiski/features/calendar/view/series_scope_dialog.dart';
import 'package:hiwiski/features/family/view/group_sheet.dart';
import 'package:hiwiski/features/family/view/invite_sheet.dart';
import 'package:hiwiski/features/todo/new_list/view/new_list_sheet.dart';
import 'package:hiwiski/features/todo/view/aisle_ui.dart';
import 'package:hiwiski/features/todo/view/kanban_columns_editor.dart';
import 'package:hiwiski/features/wiki/page/view/move_sheet.dart';
import 'package:hiwiski/core/ui/hiwiski_sheet.dart';
import 'package:hiwiski/features/wiki/page/view/revision_view.dart';
import 'package:hiwiski/features/wiki/recipe_import/view/recipe_import_sheet.dart';
import 'package:hiwiski/features/wiki/recipe_shopping/view/recipe_shopping_sheet.dart';

import 'a11y_world.dart';
import 'screens_a11y_test.dart' show settle, unmount;

/// Opens a sheet or a dialog over an empty page.
typedef Opener = void Function(
  BuildContext context,
  WidgetRef ref,
  Loaded loaded,
);

/// What a sheet is opened with, read from the family before the test.
class Loaded {
  Loaded(this.world);

  final A11yWorld world;
  late final Map<String, Object> items;

  T get<T>(String key) => items[key]! as T;
}

/// **Every sheet and dialog measured**, as the screens are (screens_a11y_test.dart).
void main() {
  final sheets = <String, Opener>{
    'share': (c, _, w) =>
        showShareSheet(c, item: ItemRef.todoList(w.world.ids['list']!)),
    'conflict': (c, _, w) => showConflictSheet(
      c,
      SyncConflict(
        id: 'c1',
        entityType: EntityTypes.todo,
        entityId: w.world.ids['todo']!,
        field: WireFields.title,
        mine: 'Call the plumber',
        theirs: 'Call the plumber today',
        detectedAt: DateTime(2026, 10, 23, 9),
      ),
    ),
    'stuck changes': (c, _, _) => showStuckSheet(c),
    'change password': (c, _, _) => showChangePasswordSheet(c),
    'restore to': (c, _, _) =>
        showRestoreTargetSheet(c, itemType: EntityTypes.todo),
    'widget settings': (c, _, w) =>
        showWidgetConfigSheet(c, widget: w.get('widget')),
    'new event': (c, _, _) => showEventSheet(c, day: DateTime(2026, 10, 23)),
    'edit event': (c, _, w) => showEventSheet(c, event: w.get('event')),
    'series scope': (c, _, _) => askSeriesScope(c, deleting: true),
    'repeat': (c, _, _) => showRecurrenceDialog(
      context: c,
      rrule: 'FREQ=WEEKLY;BYDAY=MO',
      start: DateTime(2026, 10, 26, 8),
    ),
    'new calendar': (c, _, _) => showCalendarSheet(c),
    'subscribe to a calendar': (c, _, _) => showSubscriptionSheet(c),
    'calendar feed': (c, _, _) => showFeedSheet(c),
    'import a calendar': (c, _, _) => showIcsImportSheet(c),
    'new group': (c, _, _) => showGroupSheet(c),
    'edit group': (c, _, _) => showGroupSheet(
      c,
      group: const Group(
        id: 'parents',
        name: 'Parents',
        position: 1,
        memberIds: ['anna'],
      ),
    ),
    'invite': (c, _, _) => showInviteSheet(c),
    'reset password': (c, _, _) => showPasswordResetSheet(c, ben),
    'new list': (c, _, _) => showNewListSheet(c),
    'assign': (c, _, _) => showAssigneePicker(c, {'anna'}),
    'new tag': (c, ref, _) => showNewTagDialog(c, ref),
    'category name': (c, _, _) =>
        showAisleNameSheet(c, title: 'New category', initial: 'Frozen'),
    'board columns': (c, _, w) => showEditColumnsSheet(
      c,
      list: w.get('kanban'),
      cards: w.get('cards'),
      onSave: (_) async {},
    ),
    'convert to board': (c, _, w) => showConvertToKanbanSheet(
      c,
      cards: w.get('todos'),
      onConvert: (_) async {},
    ),
    'move page': (c, _, w) => showMoveSheet(c, page: w.get('subpage')),
    'page version': (c, _, w) => showHiwiskiSheet<void>(
      context: c,
      title: 'History',
      builder: (_) =>
          RevisionView(page: w.get('page'), revisionId: 'r1', canRestore: true),
    ),
    'import recipe': (c, _, _) => showRecipeImportSheet(c, onCreated: (_) {}),
    'recipe to shopping list': (c, _, w) {
      final recipe = w.get<WikiPage>('recipe');
      showRecipeShoppingSheet(
        c,
        page: recipe,
        ingredients: Ingredient.decode(recipe.ingredients),
        servings: 4,
      );
    },
    'export a list': (c, _, w) =>
        showExportSheet(c, item: ItemRef.todoList(w.world.ids['list']!)),
    'export a page': (c, _, w) =>
        showExportSheet(c, item: ItemRef.wikiPage(w.world.ids['page']!)),
    'import': (c, _, _) => showImportSheet(
      c,
      source: ImportSource([
        TransferFile(
          'Packing.md',
          utf8.encode('- [ ] Passports\n- [x] Tickets\n'),
        ),
        TransferFile('Notes.md', utf8.encode('---\ntype: wiki_page\n---\nHi')),
        TransferFile('photo.heic', Uint8List(1)),
      ], place: .todo),
    ),
    'link picker': (c, _, _) => showLinkPicker(c),
    'link preview': (c, _, w) => showLinkPreview(
      c,
      target: LinkItem(
        itemType: EntityTypes.wikiPage,
        itemId: w.world.ids['page']!,
        title: 'Router',
        entityKey: 'WIKI-1',
      ),
      body: const Text('The password is on the box.'),
      onOpenFull: () {},
    ),
  };

  // Light and dark on both sizes; on the phone also at 200 % text, the largest
  // most phones offer — what fits at 100 % has to fit there too.
  const variants = [
    ('phone, light', Size(390, 844), Brightness.light, 1.0),
    ('phone, dark', Size(390, 844), Brightness.dark, 1.0),
    ('phone, 200 % text', Size(390, 844), Brightness.light, 2.0),
    ('tablet, light', Size(1280, 800), Brightness.light, 1.0),
    ('tablet, dark', Size(1280, 800), Brightness.dark, 1.0),
  ];

  for (final MapEntry(key: name, value: open) in sheets.entries) {
    for (final (variant, size, brightness, textScale) in variants) {
      testWidgets('$name — $variant', (tester) async {
        final world = (await tester.runAsync(A11yWorld.create))!;
        final loaded = Loaded(world);
        loaded.items = (await tester.runAsync(() => _load(world)))!;
        addTearDown(() async {
          await unmount(tester);
          await tester.runAsync(world.close);
        });
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          a11yApp(
            overrides: world.overrides(annaSession),
            brightness: brightness,
            textScale: textScale,
            home: _OpenOnce(open: open, loaded: loaded),
          ),
        );
        await settle(tester);
        final overflows = overflowsOf(tester);
        if (overflows.isNotEmpty) {
          // ignore: avoid_print
          print('Overflows:\n$overflows');
        }

        expect(world.server.unknown, isEmpty);
        await expectAccessible(tester);
        await unmount(tester);
      });
    }
  }
}

Future<Map<String, Object>> _load(A11yWorld world) =>
    world.read((container) async {
      final ids = world.ids;
      final wiki = container.read(wikiRepositoryProvider);
      final todos = container.read(todoRepositoryProvider);
      final boards = container.read(boardRepositoryProvider);
      final calendar = container.read(calendarRepositoryProvider);
      return {
        'page': (await wiki.watchPage(ids['page']!).first)!,
        'subpage': (await wiki.watchPage(ids['subpage']!).first)!,
        'recipe': (await wiki.watchPage(ids['recipe']!).first)!,
        'kanban': (await todos.watchList(ids['kanban']!).first)!,
        'cards': await todos.watchTodos(ids['kanban']!).first,
        'todos': await todos.watchTodos(ids['list']!).first,
        'widget': (await boards.watchWidgets(ids['dashboard']!).first).first,
        'event': (await calendar.watchEvent(ids['event']!).first)!,
      };
    });

/// Opens its sheet once, after the first frame — the page behind it stays empty.
class _OpenOnce extends ConsumerStatefulWidget {
  const _OpenOnce({required this.open, required this.loaded});

  final Opener open;
  final Loaded loaded;

  @override
  ConsumerState<_OpenOnce> createState() => _OpenOnceState();
}

class _OpenOnceState extends ConsumerState<_OpenOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.open(context, ref, widget.loaded),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
