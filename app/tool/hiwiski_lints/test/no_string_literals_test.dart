import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hiwiski_lints/src/no_string_literals.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoStringLiteralsTest);
  });
}

@reflectiveTest
class NoStringLiteralsTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NoStringLiterals();
    newPackage('logging').addFile('lib/logging.dart', '''
class Logger {
  Logger(String name);
  void info(Object? message) {}
}
''');
    newPackage('flutter').addFile('lib/foundation.dart', '''
typedef DebugPrintCallback = void Function(String? message);
DebugPrintCallback debugPrint = (message) {};
''');
    super.setUp();
  }

  Future<void> test_argument() async {
    await assertDiagnostics(
      r'''
void f(String s) {}
void g() => f('key');
''',
      [lint(34, 5)],
    );
  }

  Future<void> test_mapKey() async {
    await assertDiagnostics(
      r'''
final m = <String, int>{};
int? f() => m['key'];
''',
      [lint(41, 5)],
    );
  }

  Future<void> test_constContextIsNotEnough() async {
    await assertDiagnostics(
      r'''
class K {
  const K(this.s);
  final String s;
}
K f() => const K('key');
''',
      [lint(66, 5)],
    );
  }

  Future<void> test_constLocal() async {
    await assertNoDiagnostics(r'''
void f() {
  const key = 'key';
  print(key);
}
''');
  }

  Future<void> test_constTopLevel() async {
    await assertNoDiagnostics(r'''
const key = 'key';
const keys = {'a': 1, 'b': 2};
''');
  }

  Future<void> test_staticConstField() async {
    await assertNoDiagnostics(r'''
class C {
  static const key = 'key';
}
''');
  }

  Future<void> test_topLevelFinal() async {
    await assertNoDiagnostics(r'''
final pattern = RegExp(r'^[a-z]+$');
''');
  }

  Future<void> test_staticFinalField() async {
    await assertNoDiagnostics(r'''
class C {
  static final pattern = RegExp(r'^[a-z]+$');
}
''');
  }

  Future<void> test_instanceFinalField() async {
    await assertDiagnostics(
      r'''
class C {
  final key = 'key';
}
''',
      [lint(24, 5)],
    );
  }

  Future<void> test_finalLocal() async {
    await assertDiagnostics(
      r'''
void f() {
  final key = 'key';
  print(key);
}
''',
      [lint(25, 5)],
    );
  }

  Future<void> test_closureInTopLevelFinal() async {
    await assertDiagnostics(
      r'''
final f = () => 'key';
''',
      [lint(16, 5)],
    );
  }

  Future<void> test_enumArguments() async {
    await assertNoDiagnostics(r'''
enum Kind {
  event('event');

  const Kind(this.wire);
  final String wire;
}
''');
  }

  Future<void> test_annotation() async {
    await assertNoDiagnostics(r'''
@Deprecated('Use something else')
void f() {}
''');
  }

  Future<void> test_directive() async {
    await assertNoDiagnostics(r'''
import 'dart:async';

Future<void>? f;
''');
  }

  Future<void> test_withoutLetters() async {
    await assertNoDiagnostics(r'''
String f(int a, int b) =>
    ', ' + '' + '\n' + '$a/$b' + '42';
''');
  }

  Future<void> test_interpolationWithText() async {
    await assertDiagnostics(
      r'''
String f(int n) => 'items: $n';
''',
      [lint(19, 11)],
    );
  }

  Future<void> test_adjacentStringsReportedOnce() async {
    await assertDiagnostics(
      r'''
void f(String s) {}
void g() => f('a' 'b');
''',
      [lint(34, 7)],
    );
  }

  Future<void> test_defaultValue() async {
    await assertDiagnostics(
      r'''
void f({String s = 'key'}) {}
''',
      [lint(19, 5)],
    );
  }

  Future<void> test_errorMessage() async {
    await assertNoDiagnostics(r'''
void f(int n) {
  if (n < 0) throw ArgumentError('negative: $n');
  if (n > 9) throw TooLarge('too large: $n');
}

class TooLarge implements Exception {
  TooLarge(this.message);
  final String message;
}
''');
  }

  Future<void> test_namedArgumentOfException() async {
    await assertDiagnostics(
      r'''
class Failure implements Exception {
  const Failure({required this.code});
  final String code;
}
void f() => throw Failure(code: 'server.error');
''',
      [lint(131, 14)],
    );
  }

  Future<void> test_assertMessage() async {
    await assertNoDiagnostics(r'''
void f(int n) {
  assert(n >= 0, 'negative');
}
''');
  }

  Future<void> test_assertCondition() async {
    await assertDiagnostics(
      r'''
void f(String s) {
  assert(s != 'key');
}
''',
      [lint(33, 5)],
    );
  }

  Future<void> test_logLine() async {
    await assertNoDiagnostics(r'''
import 'package:logging/logging.dart';

final _log = Logger('Sync');
void f(int n) => _log.info('pulled $n items');
''');
  }

  Future<void> test_keyInsideMessageIsStillReported() async {
    await assertDiagnostics(
      r'''
String g(String s) => s;
void f() => throw ArgumentError(g('key'));
''',
      [lint(59, 5)],
    );
  }

  Future<void> test_debugPrint() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/foundation.dart';

void f() => debugPrint('started');
''');
  }

  Future<void> test_toString() async {
    await assertNoDiagnostics(r'''
class Segment {
  final int start = 0;
  @override
  String toString() => 'Segment($start)';
}
''');
  }
}
