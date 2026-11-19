import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hiwiski_lints/src/no_magic_dimensions.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoMagicDimensionsTest);
  });
}

@reflectiveTest
class NoMagicDimensionsTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = NoMagicDimensions();
    newPackage('flutter').addFile('lib/widgets.dart', '''
class EdgeInsets {
  const EdgeInsets.all(double value);
  const EdgeInsets.only({double left = 0, double top = 0});
}
class Radius {
  const Radius.circular(double radius);
  static Radius? lerp(Radius? a, Radius? b, double t) => a;
}
class Widget {
  const Widget();
}
class SizedBox extends Widget {
  const SizedBox({double? width, double? height});
}
class Icon extends Widget {
  const Icon({double? size, double? fill});
}
class Text extends Widget {
  const Text(String data, {int? maxLines});
}
class Interval {
  const Interval(double begin, double end);
}
''');
    newPackage('picker').addFile('lib/picker.dart', '''
void pick({double? maxWidth}) {}
''');
    super.setUp();
  }

  Future<void> test_geometryPositional() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
const p = EdgeInsets.all(8);
''',
      [lint(64, 1)],
    );
  }

  Future<void> test_geometryNamed() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
const p = EdgeInsets.only(left: 0, top: 4);
''',
      [lint(79, 1)],
    );
  }

  Future<void> test_geometryDotShorthand() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
const EdgeInsets p = .all(9);
''',
      [lint(65, 1)],
    );
  }

  Future<void> test_geometryDotShorthandAsArgument() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
class Box extends Widget {
  const Box({EdgeInsets? padding});
}
Widget f() => const Box(padding: .only(top: 6));
''',
      [lint(148, 1)],
    );
  }

  Future<void> test_geometryMethodIsNoMeasurement() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
final r = Radius.lerp(null, null, 0.5);
''');
  }

  Future<void> test_localOutsideAClosure() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
Widget f() {
  final gap = 12.0;
  return g((context) => SizedBox(width: gap));
}
Widget g(Widget Function(Object) build) => build(0);
''',
      [lint(112, 3)],
    );
  }

  Future<void> test_dimensionName() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
Widget f() => const SizedBox(height: 12.0);
''',
      [lint(76, 4)],
    );
  }

  Future<void> test_iconSize() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
Widget f() => const Icon(size: 20, fill: 1);
''',
      [lint(70, 2)],
    );
  }

  Future<void> test_zero() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
Widget f() => const SizedBox(width: 0);
''');
  }

  Future<void> test_notADimension() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
Widget f() => const Text('a', maxLines: 2);
const i = Interval(0.2, 0.8);
''');
  }

  Future<void> test_thirdPartyPackage() async {
    await assertNoDiagnostics(r'''
import 'package:picker/picker.dart';
void f() => pick(maxWidth: 2048);
''');
  }

  Future<void> test_tokens() async {
    newFile('$testPackageLibPath/core/theme/hiwiski_metrics.dart', r'''
class HiwiskiMetrics {
  static const double space8 = 8;
}
''');
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
import 'core/theme/hiwiski_metrics.dart';
Widget f() => const SizedBox(width: HiwiskiMetrics.space8);
''');
  }

  Future<void> test_factor() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
Widget f(double size) => SizedBox(width: size / 2, height: size * 3);
''');
  }

  Future<void> test_sum() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
Widget f(double size) => SizedBox(width: size + 2);
''',
      [lint(87, 1)],
    );
  }

  Future<void> test_negative() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
const p = EdgeInsets.only(top: -4);
''',
      [lint(71, 1)],
    );
  }

  Future<void> test_conditional() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
Widget f(bool b) => SizedBox(width: b ? 8 : 0);
''',
      [lint(79, 1)],
    );
  }

  Future<void> test_privateConstant() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
const _gap = 7.0;
Widget f() => const SizedBox(width: _gap);
''',
      [lint(93, 4)],
    );
  }

  Future<void> test_localVariable() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
Widget f() {
  final size = 18.0;
  return SizedBox(width: size);
}
''',
      [lint(98, 4)],
    );
  }

  Future<void> test_ownWidget() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
class Avatar extends Widget {
  const Avatar({this.radius = 13});
  final double radius;
}
Widget f() => const Avatar(radius: 20);
''',
      [lint(99, 2), lint(165, 2)],
    );
  }

  Future<void> test_themeDirectory() async {
    final file = newFile('$testPackageLibPath/core/theme/metrics.dart', r'''
import 'package:flutter/widgets.dart';
const p = EdgeInsets.all(8);
''');
    await assertNoDiagnosticsInFile(file.path);
  }
}
