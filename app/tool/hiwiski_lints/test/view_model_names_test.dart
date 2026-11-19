import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hiwiski_lints/src/view_model_names.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ViewModelNamesTest);
  });

  group('allowedViewModelFiles', () {
    test('a screen folder names its ViewModel', () {
      expect(
        allowedViewModelFiles('features/todo/kanban/kanban_view_model.dart'),
        ['kanban_view_model.dart', 'todo_kanban_view_model.dart'],
      );
      expect(allowedViewModelFiles('features/search/search_view_model.dart'), [
        'search_view_model.dart',
      ]);
      expect(allowedViewModelFiles('components/tags/tags_view_model.dart'), [
        'tags_view_model.dart',
      ]);
      expect(
        allowedViewModelFiles('core/shell/shell_view_model.dart'),
        isEmpty,
      );
    });
  });
}

@reflectiveTest
class ViewModelNamesTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ViewModelNames();
    newPackage('riverpod_annotation')
        .addFile('lib/riverpod_annotation.dart', '''
class Riverpod {
  const Riverpod({bool keepAlive = false});
}
const riverpod = Riverpod();
''');
    newPackage('flutter_riverpod').addFile('lib/flutter_riverpod.dart', '''
abstract class Notifier<T> {
  T build();
}
class ConsumerWidget {}
''');
    super.setUp();
  }

  String _write(String path, String content) {
    final file = '$testPackageLibPath/$path';
    newFile(file, content);
    return file;
  }

  Future<void> test_aViewModelInItsFolder() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
class KanbanState {}
@riverpod
class KanbanViewModel {
  KanbanState build() => KanbanState();
}
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/kanban/kanban_view_model.dart', content),
    );
    await assertNoDiagnosticsInFile(
      _write('features/todo/overview/todo_overview_view_model.dart', content),
    );
  }

  Future<void> test_aController() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
class KanbanController {
  void build() {}
}
''';
    await assertDiagnosticsInFile(
      _write('features/todo/kanban/kanban_view_model.dart', content),
      [lint(content.indexOf('KanbanController'), 'KanbanController'.length)],
    );
  }

  Future<void> test_aNotifierWithoutCodegen() async {
    const content = '''
import 'package:flutter_riverpod/flutter_riverpod.dart';
class FilterNotifier extends Notifier<int> {
  @override
  int build() => 0;
}
''';
    await assertDiagnosticsInFile(
      _write('features/todo/kanban/kanban_view_model.dart', content),
      [lint(content.indexOf('FilterNotifier'), 'FilterNotifier'.length)],
    );
  }

  Future<void> test_aViewModelOutsideAViewModelFile() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
class KanbanViewModel {
  void build() {}
}
''';
    await assertDiagnosticsInFile(
      _write('features/todo/list_page.dart', content),
      [lint(content.indexOf('KanbanViewModel'), 'KanbanViewModel'.length)],
    );
  }

  Future<void> test_aFileNotNamedAfterItsFolder() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
class BoardViewModel {
  void build() {}
}
''';
    await assertDiagnosticsInFile(
      _write('features/todo/kanban/board_view_model.dart', content),
      [lint(0, content.indexOf('\n'))],
    );
  }

  Future<void> test_aStateNotEndingInState() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
class KanbanColumns {}
@riverpod
class KanbanViewModel {
  KanbanColumns build() => KanbanColumns();
}
''';
    await assertDiagnosticsInFile(
      _write('features/todo/kanban/kanban_view_model.dart', content),
      [lint(content.indexOf('KanbanColumns build'), 'KanbanColumns'.length)],
    );
  }

  Future<void> test_aStateFromElsewhereIsNotOurs() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
class KanbanViewModel {
  List<int> build() => const [];
}
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/kanban/kanban_view_model.dart', content),
    );
  }

  Future<void> test_aConsumerWidgetIsNoProviderClass() async {
    const content = '''
import 'package:flutter_riverpod/flutter_riverpod.dart';
class KanbanScreen extends ConsumerWidget {}
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/kanban/view/kanban_screen.dart', content),
    );
  }

  Future<void> test_theCompositionRootIsExempt() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
class SessionValue {
  void build() {}
}
''';
    await assertNoDiagnosticsInFile(_write('app/stores.dart', content));
  }
}
