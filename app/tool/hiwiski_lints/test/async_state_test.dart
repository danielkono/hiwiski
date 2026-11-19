import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hiwiski_lints/src/async_state.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AsyncStateTest);
  });
}

@reflectiveTest
class AsyncStateTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = AsyncState();
    newPackage('riverpod').addFile('lib/riverpod.dart', '''
class AsyncValue<T> {
  bool get isLoading => false;
  R when<R>({
    bool skipLoadingOnReload = false,
    required R Function(T) data,
    required R Function(Object, StackTrace) error,
    required R Function() loading,
  }) => loading();
}
class Ref {}
''');
    super.setUp();
  }

  String _write(String path, String content) {
    final file = '$testPackageLibPath/$path';
    newFile(file, content);
    return file;
  }

  Future<void> test_whenWithoutSkip() async {
    const content = '''
import 'package:riverpod/riverpod.dart';
int show(AsyncValue<int> state) =>
    state.when(data: (v) => v, error: (_, _) => 0, loading: () => 0);
''';
    await assertDiagnosticsInFile(
      _write('features/todo/kanban/view/kanban_screen.dart', content),
      [lint(content.indexOf('when'), 'when'.length)],
    );
  }

  Future<void> test_whenWithSkip() async {
    const content = '''
import 'package:riverpod/riverpod.dart';
int show(AsyncValue<int> state) => state.when(
  skipLoadingOnReload: true,
  data: (v) => v,
  error: (_, _) => 0,
  loading: () => 0,
);
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/kanban/view/kanban_screen.dart', content),
    );
  }

  Future<void> test_isLoadingInAView() async {
    const content = '''
import 'package:riverpod/riverpod.dart';
bool strip(AsyncValue<int> state) => state.isLoading;
''';
    await assertDiagnosticsInFile(
      _write('features/todo/kanban/view/kanban_screen.dart', content),
      [lint(content.indexOf('isLoading'), 'isLoading'.length)],
    );
  }

  Future<void> test_loadingFlagInAState() async {
    const content = '''
class KanbanState {
  const KanbanState({required this.loading});
  final bool loading;
}
''';
    await assertDiagnosticsInFile(
      _write('features/todo/kanban/kanban_view_model.dart', content),
      [lint(content.indexOf('loading;'), 'loading'.length)],
    );
  }

  Future<void> test_aSharedWatcher() async {
    const content = '''
import 'package:riverpod/riverpod.dart';
int watchListPage(Ref ref, String listId) => 0;
''';
    await assertDiagnosticsInFile(
      _write('features/todo/list_page.dart', content),
      [lint(content.indexOf('watchListPage'), 'watchListPage'.length)],
    );
  }

  Future<void> test_aWatcherInsideItsViewModel() async {
    const content = '''
import 'package:riverpod/riverpod.dart';
int _items(Ref ref, String listId) => 0;
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/kanban/kanban_view_model.dart', content),
    );
  }
}
