import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hiwiski_lints/src/layer_boundaries.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(LayerBoundariesTest);
  });

  group('layerOf', () {
    test('folders decide the layer', () {
      expect(layerOf('main.dart'), Layer.composition);
      expect(layerOf('app/repositories.dart'), Layer.composition);
      expect(layerOf('core/common/wire.dart'), Layer.common);
      expect(layerOf('core/api/generated/export.dart'), Layer.models);
      expect(layerOf('core/api/hiwiski_failure.dart'), Layer.models);
      expect(layerOf('core/api/hiwiski_api.dart'), Layer.service);
      expect(layerOf('core/db/tables.dart'), Layer.service);
      expect(layerOf('data/todo/r_repository.dart'), Layer.model);
      expect(layerOf('domain/todo/m.dart'), Layer.domain);
      expect(
        layerOf('features/todo/list/todo_list_view_model.dart'),
        Layer.viewModel,
      );
      expect(layerOf('features/todo/list_page.dart'), Layer.viewModel);
      expect(layerOf('core/shell/shell_view_model.dart'), Layer.viewModel);
      expect(layerOf('components/tags/tags_view_model.dart'), Layer.viewModel);
      expect(layerOf('features/todo/list/view/v.dart'), Layer.view);
      expect(layerOf('components/tags/view/v.dart'), Layer.view);
      expect(layerOf('core/ui/states.dart'), Layer.view);
      expect(layerOf('core/misc.dart'), isNull);
    });

    test('a view belongs to the folder holding its view/ folder', () {
      expect(homeOf('features/todo/list/view/v.dart'), 'features/todo/list');
      expect(homeOf('features/todo/view/parts/v.dart'), 'features/todo');
      expect(homeOf('core/shell/app_shell.dart'), 'core/shell');
    });
  });

  group('violation', () {
    test('a view reaches only its own ViewModel', () {
      const view = 'features/todo/list/view/v.dart';
      expect(
        violation(view, 'features/todo/list/todo_list_view_model.dart'),
        isNull,
      );
      expect(violation(view, 'features/todo/list_page.dart'), isNull);
      expect(violation(view, 'features/todo/view/row.dart'), isNull);
      expect(violation(view, 'components/tags/view/tags.dart'), isNull);
      expect(violation(view, 'core/routing/routes.dart'), isNull);
      expect(violation(view, 'domain/todo/m.dart'), isNull);
      expect(violation(view, 'core/common/wire.dart'), isNull);
      expect(violation(view, 'core/api/generated/export.dart'), isNull);
      expect(
        violation(view, 'features/todo/detail/todo_detail_view_model.dart'),
        isNotNull,
      );
      expect(
        violation(view, 'components/tags/tags_view_model.dart'),
        isNotNull,
      );
      expect(violation(view, 'data/todo/r_repository.dart'), isNotNull);
      expect(violation(view, 'core/db/hiwiski_database.dart'), isNotNull);
      expect(violation(view, 'app/repositories.dart'), isNotNull);
      expect(violation(view, 'app/stores.dart'), isNotNull);
    });

    test('a feature-level view reaches no screen ViewModel', () {
      const view = 'features/todo/view/row.dart';
      expect(violation(view, 'features/todo/list_page.dart'), isNull);
      expect(
        violation(view, 'features/todo/list/todo_list_view_model.dart'),
        isNotNull,
      );
    });

    test('features stay apart', () {
      const view = 'features/todo/list/view/v.dart';
      expect(violation(view, 'features/wiki/page/view/p.dart'), isNotNull);
      expect(
        violation(
          'features/todo/list/todo_list_view_model.dart',
          'features/wiki/w.dart',
        ),
        isNotNull,
      );
      expect(
        violation('components/tags/view/t.dart', 'features/todo/view/row.dart'),
        isNotNull,
      );
      expect(
        violation('core/ui/x.dart', 'features/todo/view/row.dart'),
        isNotNull,
      );
      expect(
        violation('core/routing/routes.dart', 'features/todo/list/view/v.dart'),
        isNull,
      );
    });

    test('a ViewModel reaches the model, not another ViewModel', () {
      const viewModel = 'features/todo/list/todo_list_view_model.dart';
      expect(violation(viewModel, 'data/wiki/r_repository.dart'), isNull);
      expect(violation(viewModel, 'domain/todo/m.dart'), isNull);
      expect(violation(viewModel, 'core/sync/sync_status.dart'), isNull);
      expect(violation(viewModel, 'app/repositories.dart'), isNull);
      expect(violation(viewModel, 'app/stores.dart'), isNull);
      expect(violation(viewModel, 'app/link_index.dart'), isNull);
      expect(violation(viewModel, 'features/todo/list_page.dart'), isNull);
      expect(violation(viewModel, 'app/data_providers.dart'), isNotNull);
      expect(violation(viewModel, 'app/router.dart'), isNotNull);
      expect(violation(viewModel, 'features/todo/list/view/v.dart'), isNotNull);
      expect(
        violation(
          viewModel,
          'features/todo/detail/todo_detail_view_model.dart',
        ),
        isNotNull,
      );
      expect(
        violation(viewModel, 'components/tags/tags_view_model.dart'),
        isNotNull,
      );
    });

    test('the model knows the services and the domain, not its neighbours', () {
      const repository = 'data/todo/r_repository.dart';
      expect(violation(repository, 'core/db/hiwiski_database.dart'), isNull);
      expect(violation(repository, 'data/todo/o_repository.dart'), isNull);
      expect(violation(repository, 'data/query.dart'), isNull);
      expect(violation(repository, 'domain/tags/m.dart'), isNull);
      expect(violation(repository, 'data/tags/r_repository.dart'), isNotNull);
      expect(
        violation(repository, 'features/todo/list/todo_list_view_model.dart'),
        isNotNull,
      );
      expect(violation(repository, 'app/stores.dart'), isNotNull);
    });

    test('the domain stays pure', () {
      const domain = 'domain/todo/m.dart';
      expect(violation(domain, 'domain/common/item_ref.dart'), isNull);
      expect(violation(domain, 'core/common/ids.dart'), isNull);
      expect(violation(domain, 'core/sync/outbox.dart'), isNotNull);
      expect(violation(domain, 'data/todo/r_repository.dart'), isNotNull);
    });

    test('the services stay below everything', () {
      const service = 'core/sync/sync_engine.dart';
      expect(violation(service, 'core/db/hiwiski_database.dart'), isNull);
      expect(violation(service, 'core/common/wire.dart'), isNull);
      expect(violation(service, 'domain/todo/m.dart'), isNotNull);
      expect(violation(service, 'data/todo/r_repository.dart'), isNotNull);
    });
  });
}

@reflectiveTest
class LayerBoundariesTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = LayerBoundaries();
    newPackage('riverpod_annotation')
        .addFile('lib/riverpod_annotation.dart', '''
class Ref {}
const riverpod = Object();
''');
    newPackage('hooks_riverpod').addFile('lib/hooks_riverpod.dart', '''
class HookRef {}
''');
    newPackage('flutter')
      ..addFile('lib/foundation.dart', 'const kIsWeb = false;')
      ..addFile('lib/src/widgets/framework.dart', 'class Widget {}');
    super.setUp();
  }

  String _write(String path, String content) {
    final file = '$testPackageLibPath/$path';
    newFile(file, content);
    return file;
  }

  /// Where the quoted [uri] starts in [content].
  int _offset(String content, String uri) => content.indexOf("'$uri'");

  Future<void> test_viewImportsItsViewModel() async {
    _write('features/todo/list/todo_list_view_model.dart', 'int c = 0;');
    const content = '''
import '../todo_list_view_model.dart';
int v = c;
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/list/view/v.dart', content),
    );
  }

  Future<void> test_viewImportsAnotherViewModel() async {
    _write('features/todo/detail/todo_detail_view_model.dart', 'int c = 0;');
    const content = '''
import '../../detail/todo_detail_view_model.dart';
int v = c;
''';
    await assertDiagnosticsInFile(
      _write('features/todo/list/view/v.dart', content),
      [
        lint(
          _offset(content, '../../detail/todo_detail_view_model.dart'),
          '../../detail/todo_detail_view_model.dart'.length + 2,
        ),
      ],
    );
  }

  Future<void> test_viewDeclaresProvider() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
int count(Ref ref) => 0;
''';
    await assertDiagnosticsInFile(
      _write('features/todo/list/view/v.dart', content),
      [error(LayerBoundaries.providerInView, 63, 9)],
    );
  }

  Future<void> test_viewModelDeclaresProvider() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
@riverpod
int count(Ref ref) => 0;
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/list/todo_list_view_model.dart', content),
    );
  }

  Future<void> test_passiveWidgetImportsRiverpod() async {
    const content = '''
import 'package:hooks_riverpod/hooks_riverpod.dart';
HookRef? ref;
''';
    await assertDiagnosticsInFile(_write('core/ui/w.dart', content), [
      lint(
        _offset(content, 'package:hooks_riverpod/hooks_riverpod.dart'),
        'package:hooks_riverpod/hooks_riverpod.dart'.length + 2,
      ),
    ]);
  }

  Future<void> test_featureImportsAnotherFeature() async {
    _write('features/wiki/page/view/p.dart', 'int p = 0;');
    const content = '''
import 'package:test/features/wiki/page/view/p.dart';
int v = p;
''';
    await assertDiagnosticsInFile(
      _write('features/todo/list/view/v.dart', content),
      [
        lint(
          _offset(content, 'package:test/features/wiki/page/view/p.dart'),
          'package:test/features/wiki/page/view/p.dart'.length + 2,
        ),
      ],
    );
  }

  Future<void> test_viewImportsDatabase() async {
    _write('core/db/hiwiski_database.dart', 'int db = 0;');
    const content = '''
import '../../../../core/db/hiwiski_database.dart';
int v = db;
''';
    await assertDiagnosticsInFile(
      _write('features/todo/list/view/v.dart', content),
      [
        lint(
          _offset(content, '../../../../core/db/hiwiski_database.dart'),
          '../../../../core/db/hiwiski_database.dart'.length + 2,
        ),
      ],
    );
  }

  Future<void> test_viewImportsRepositoryByPackage() async {
    _write('data/todo/r_repository.dart', 'int r = 0;');
    const content = '''
import 'package:test/data/todo/r_repository.dart';
int v = r;
''';
    await assertDiagnosticsInFile(
      _write('features/todo/list/view/v.dart', content),
      [
        lint(
          _offset(content, 'package:test/data/todo/r_repository.dart'),
          'package:test/data/todo/r_repository.dart'.length + 2,
        ),
      ],
    );
  }

  Future<void> test_repositoryImportsRiverpod() async {
    const content = '''
import 'package:riverpod_annotation/riverpod_annotation.dart';
Ref? ref;
''';
    await assertDiagnosticsInFile(
      _write('data/todo/r_repository.dart', content),
      [
        lint(
          _offset(
            content,
            'package:riverpod_annotation/riverpod_annotation.dart',
          ),
          'package:riverpod_annotation/riverpod_annotation.dart'.length + 2,
        ),
      ],
    );
  }

  Future<void> test_repositoryImportsHooksRiverpod() async {
    const content = '''
import 'package:hooks_riverpod/hooks_riverpod.dart';
HookRef? ref;
''';
    await assertDiagnosticsInFile(
      _write('data/todo/r_repository.dart', content),
      [
        lint(
          _offset(content, 'package:hooks_riverpod/hooks_riverpod.dart'),
          'package:hooks_riverpod/hooks_riverpod.dart'.length + 2,
        ),
      ],
    );
  }

  Future<void> test_repositoryImportsFlutterInternals() async {
    const content = '''
import 'package:flutter/src/widgets/framework.dart';
Widget? w;
''';
    await assertDiagnosticsInFile(
      _write('data/todo/r_repository.dart', content),
      [
        lint(
          _offset(content, 'package:flutter/src/widgets/framework.dart'),
          'package:flutter/src/widgets/framework.dart'.length + 2,
        ),
      ],
    );
  }

  Future<void> test_repositoryImportsFoundation() async {
    const content = '''
import 'package:flutter/foundation.dart';
bool web = kIsWeb;
''';
    await assertNoDiagnosticsInFile(
      _write('data/todo/r_repository.dart', content),
    );
  }

  Future<void> test_viewModelImportsRepositoryProviders() async {
    _write('app/repositories.dart', 'int providers = 0;');
    const content = '''
import '../../../app/repositories.dart';
int c = providers;
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/list/todo_list_view_model.dart', content),
    );
  }

  Future<void> test_fileWithoutLayer() async {
    const content = '''
int x = 0;
''';
    await assertDiagnosticsInFile(_write('core/misc.dart', content), [
      error(LayerBoundaries.unplaced, 0, 10),
    ]);
  }

  Future<void> test_compositionRootImportsAnything() async {
    _write('core/db/hiwiski_database.dart', 'int db = 0;');
    const content = '''
import 'core/db/hiwiski_database.dart';
int m = db;
''';
    await assertNoDiagnosticsInFile(_write('main.dart', content));
  }
}
