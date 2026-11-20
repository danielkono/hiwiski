import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/link_index.dart';
import 'package:hiwiski/components/rich_text/view/markdown_text_controller.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/core/ui/edit_actions.dart';
import 'package:hiwiski/core/ui/ui_keys.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:hiwiski/features/todo/view/list_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Saving waits for the images being added.** Picked on an iPhone, photos are
/// converted and read before they go into the text — a few seconds for several — and
/// a save in between went out without them.
void main() {
  const image = '![](hiwiski-image:a)';

  group('the controller', () {
    test('with no images on their way, nothing is waited for', () async {
      final controller = MarkdownTextController();
      addTearDown(controller.dispose);
      bool done = false;
      unawaited(controller.imagesAdded.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isTrue);
    });

    test('it is done once the images are in the text', () async {
      final controller = MarkdownTextController(text: 'Before');
      addTearDown(controller.dispose);
      final read = Completer<void>();
      unawaited(
        controller.addImages(() async {
          await read.future;
          controller.text = '${controller.text}\n$image';
        }),
      );
      String? saved;
      unawaited(controller.imagesAdded.then((_) => saved = controller.text));
      await pumpEventQueue();
      expect(saved, isNull);

      read.complete();
      await pumpEventQueue();
      expect(saved, equals('Before\n$image'));
    });
  });

  testWidgets('a list saved while images are on their way saves them along', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final local = (await tester.runAsync(LocalSettings.open))!;
    final db = HiwiskiDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final saves = <String?>[];
    const list = TodoList(
      id: 'l1',
      ownerId: 'anna',
      version: 1,
      name: 'Chores',
      kind: 'STANDARD',
      colorToken: 'BLUE',
      position: 0,
      assignees: '',
      tags: '',
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          databaseProvider.overrideWithValue(db),
          localSettingsProvider.overrideWithValue(local),
          linkIndexProvider.overrideWithValue(LinkIndex.from(const [])),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: L.localizationsDelegates,
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListEditor(
                list: list,
                done: 0,
                onSave: ({required name, required description}) =>
                    saves.add(description),
              ),
            ),
          ),
        ),
      ),
    );
    final description = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller)
        .whereType<MarkdownTextController>()
        .single;
    final read = Completer<void>();
    unawaited(
      description.addImages(() async {
        await read.future;
        description.text = image;
      }),
    );

    final editor = tester.state<ListEditorState>(find.byType(ListEditor));
    unawaited(editor.save());
    // Tapped again while waiting: still one save.
    unawaited(editor.save());
    await tester.pump();
    expect(saves, isEmpty);

    read.complete();
    await tester.pump();
    expect(saves, equals([image]));
  });

  testWidgets('"Save" is greyed out while images are being added', (
    tester,
  ) async {
    final controller = MarkdownTextController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: EditActions(
            editing: true,
            onEdit: () {},
            onSave: () {},
            onCancel: () {},
            saveBlocked: MarkdownTextController.addingImagesAnywhere,
          ),
        ),
      ),
    );
    bool saveEnabled() =>
        tester.widget<FilledButton>(find.byKey(CoreKeys.editSave)).enabled;
    expect(saveEnabled(), isTrue);

    final read = Completer<void>();
    final adding = controller.addImages(() => read.future);
    await tester.pump();
    expect(saveEnabled(), isFalse);

    read.complete();
    await adding;
    await tester.pump();
    expect(saveEnabled(), isTrue);
  });
}
