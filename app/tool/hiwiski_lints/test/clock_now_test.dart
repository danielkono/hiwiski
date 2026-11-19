import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hiwiski_lints/src/clock_now.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ClockNowTest);
  });
}

@reflectiveTest
class ClockNowTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ClockNow();
    super.setUp();
  }

  Future<void> test_now() async {
    const content = 'final today = DateTime.now();\n';
    await assertDiagnostics(content, [
      lint(content.indexOf('DateTime.now()'), 'DateTime.now()'.length),
    ]);
  }

  Future<void> test_aDateTimeOfItsOwn() async {
    await assertNoDiagnostics('''
class DateTime {
  DateTime.now();
}
final today = DateTime.now();
''');
  }
}
