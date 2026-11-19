import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Reports `DateTime.now()` and `DateTime.timestamp()` in the app: the time is read
/// as `clock.now()` from `package:clock`.
///
/// `DateTime.now()` cannot be changed by a test. `clock.now()` follows the zone, so a
/// test can fix the day with `withClock`. The store screenshots depend on that: they
/// are golden files, and a single date taken from the real clock would make them
/// differ every day. `test/` is exempt.
class ClockNow extends AnalysisRule {
  static const LintCode code = LintCode(
    'clock_now',
    'The time read from DateTime instead of package:clock.',
    correctionMessage: 'Use clock.now() from package:clock.',
  );

  ClockNow()
    : super(
        name: 'clock_now',
        description: 'The app reads the time through package:clock.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    registry.addInstanceCreationExpression(this, _Visitor(this));
  }
}

/// The constructors of `DateTime` that read the device's clock.
const _clockConstructors = {'now', 'timestamp'};

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName;
    if (!_clockConstructors.contains(constructor.name?.name)) return;
    final element = constructor.type.element;
    if (element?.name != 'DateTime') return;
    if (element?.library?.uri.toString() != 'dart:core') return;
    rule.reportAtNode(node);
  }
}
