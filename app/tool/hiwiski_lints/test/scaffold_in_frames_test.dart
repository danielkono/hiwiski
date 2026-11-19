import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hiwiski_lints/src/scaffold_in_frames.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ScaffoldInFramesTest);
  });
}

@reflectiveTest
class ScaffoldInFramesTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ScaffoldInFrames();
    newPackage('flutter').addFile('lib/material.dart', '''
class Widget {
  const Widget();
}
class Scaffold extends Widget {
  const Scaffold({Widget? body});
}
''');
    super.setUp();
  }

  String _write(String path, String content) {
    final file = '$testPackageLibPath/$path';
    newFile(file, content);
    return file;
  }

  static const _screen = '''
import 'package:flutter/material.dart';
Widget build() => Scaffold();
''';

  Future<void> test_screenBuildsAScaffold() async {
    await assertDiagnosticsInFile(
      _write('features/todo/view/todo_screen.dart', _screen),
      [lint(_screen.indexOf('Scaffold()'), 'Scaffold'.length)],
    );
  }

  Future<void> test_framesBuildOne() async {
    for (final frame in frames) {
      await assertNoDiagnosticsInFile(_write(frame, _screen));
    }
  }

  Future<void> test_aScaffoldOfItsOwnIsNoFlutterScaffold() async {
    const content = '''
class Scaffold {
  const Scaffold();
}
final s = Scaffold();
''';
    await assertNoDiagnosticsInFile(
      _write('features/todo/view/todo_screen.dart', content),
    );
  }
}
