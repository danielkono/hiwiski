import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hiwiski_lints/src/view_model_commands.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ViewModelCommandsTest);
  });
}

@reflectiveTest
class ViewModelCommandsTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ViewModelCommands();
    super.setUp();
  }

  Future<void> test_commands() async {
    await assertNoDiagnostics(r'''
import 'dart:async';
class PageViewModel {
  int build() => 0;
  void rename(String name) {}
  Future<void> archive() async {}
  FutureOr<void> restore() {}
}
''');
  }

  Future<void> test_resultOfACommand() async {
    await assertDiagnostics(
      r'''
class PageViewModel {
  Future<int> subpages() async => 0;
}
''',
      [lint(36, 8)],
    );
  }

  Future<void> test_syncResult() async {
    await assertDiagnostics(
      r'''
class PageViewModel {
  bool move() => true;
}
''',
      [lint(29, 4)],
    );
  }

  Future<void> test_privateGettersStaticAreFine() async {
    await assertNoDiagnostics(r'''
class PageViewModel {
  int get count => 0;
  static int parse(String s) => 0;
  int _helper() => 0;
  void use() => _helper();
}
''');
  }

  Future<void> test_markedCommand() async {
    newFile('$testPackageLibPath/core/common/command.dart', r'''
const command = Command._();
final class Command {
  const Command._();
}
''');
    await assertNoDiagnostics(r'''
import 'core/common/command.dart';
class NewListViewModel {
  @command
  Future<String> create() async => 'id';
}
''');
  }

  Future<void> test_anotherCommandAnnotation() async {
    await assertDiagnostics(
      r'''
const command = 0;
class NewListViewModel {
  @command
  Future<String> create() async => 'id';
}
''',
      [lint(72, 6)],
    );
  }

  Future<void> test_notAViewModel() async {
    await assertNoDiagnostics(r'''
class PageRepository {
  Future<int> subpages() async => 0;
}
''');
  }
}
