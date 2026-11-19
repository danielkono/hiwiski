import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

/// Reports every raw number used as a measurement: a padding, a gap, a width or
/// height, a radius, an icon size, a stroke or an elevation.
///
/// A measurement written into a screen is a value nobody finds again, and the
/// next screen picks a slightly different one. Measurements come from
/// `HiwiskiMetrics` (`lib/core/theme/`), so the scale stays one scale.
///
/// A measurement is:
/// - any argument of `EdgeInsets`, `EdgeInsetsDirectional`, `BorderRadius`,
///   `BorderRadiusDirectional`, `Radius`, `BoxConstraints`, `Size`,
///   `Positioned` and `PositionedDirectional`;
/// - a named argument of type `double` whose name says it is one (`width`,
///   `size`, `radius`, `spacing`, ...) -- of Flutter's API and of the app's own
///   widgets, not of third-party packages (an image picker's `maxWidth` is not a
///   layout value);
/// - the default value of such a parameter in the app's own widgets.
///
/// The number is found where it hides, too: behind a unary minus, in either
/// branch of a conditional, in a sum or difference (`space8 + 2` is a 10 nobody
/// named), and behind a constant or local variable declared outside
/// `lib/core/theme/`. A factor stays allowed: `size / 2` and `space4 * 3` derive
/// a value, they do not invent one.
///
/// Allowed are `0` and everything under `lib/core/theme/` and `test/`.
class NoMagicDimensions extends AnalysisRule {
  static const LintCode code = LintCode(
    'no_magic_dimensions',
    'Raw number used as a measurement.',
    correctionMessage:
        'Use a measurement from HiwiskiMetrics, or add the missing one there.',
  );

  NoMagicDimensions()
    : super(
        name: 'no_magic_dimensions',
        description: 'Measurements come from HiwiskiMetrics.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    final path = context.definingUnit.file.path.replaceAll(r'\', '/');
    if (path.contains(_themeDirectory)) return;
    final library = context.libraryElement?.uri;
    final visitor = _Visitor(
      this,
      package: library != null && library.isScheme('package')
          ? library.pathSegments.first
          : null,
    );
    registry.addArgumentList(this, visitor);
    registry.addFormalParameterDefaultClause(this, visitor);
  }
}

const _themeDirectory = '/lib/core/theme/';

/// Classes whose every argument is a measurement.
const _geometry = {
  'EdgeInsets',
  'EdgeInsetsDirectional',
  'BorderRadius',
  'BorderRadiusDirectional',
  'Radius',
  'BoxConstraints',
  'Size',
  'Positioned',
  'PositionedDirectional',
};

/// Parameter names that make a `double` a measurement.
const _dimensionNames = {
  'width',
  'height',
  'size',
  'iconSize',
  'opticalSize',
  'dimension',
  'radius',
  'minRadius',
  'maxRadius',
  'spacing',
  'runSpacing',
  'mainAxisSpacing',
  'crossAxisSpacing',
  'elevation',
  'scrolledUnderElevation',
  'thickness',
  'indent',
  'endIndent',
  'strokeWidth',
  'minWidth',
  'maxWidth',
  'minHeight',
  'maxHeight',
  'minExtent',
  'maxExtent',
  'itemExtent',
  'extent',
  'toolbarHeight',
  'leadingWidth',
  'titleSpacing',
  'horizontalTitleGap',
  'minLeadingWidth',
  'minTileHeight',
  'minVerticalPadding',
  'blurRadius',
  'spreadRadius',
  'gap',
};

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, {required this.package});

  final AnalysisRule rule;

  /// The package the analyzed library belongs to: its own widgets count.
  final String? package;

  @override
  void visitArgumentList(ArgumentList node) {
    final geometry = _isGeometry(node.parent);
    for (final argument in node.arguments) {
      final parameter = argument.correspondingParameter;
      if (parameter == null) continue;
      if (!geometry && !_isDimension(parameter)) continue;
      for (final offender in _rawNumbers(argument.argumentExpression)) {
        rule.reportAtNode(offender);
      }
    }
  }

  @override
  void visitFormalParameterDefaultClause(FormalParameterDefaultClause node) {
    final parameter = node.parent;
    if (parameter is! FormalParameter) return;
    final element = parameter.declaredFragment?.element;
    if (element == null || !_isDimension(element)) return;
    for (final offender in _rawNumbers(node.value)) {
      rule.reportAtNode(offender);
    }
  }

  /// A geometry *constructor* — `EdgeInsets.all`, `BorderRadius.circular` are
  /// constructors too. Not every method of those classes: `BorderRadius.lerp(a, b,
  /// 0.5)` reported its interpolation factor as a measurement.
  ///
  /// A dot shorthand (`padding: .all(8)`) is a constructor call as well, only
  /// without the class name in front.
  bool _isGeometry(AstNode? call) {
    final element = switch (call) {
      InstanceCreationExpression(:final constructorName) =>
        constructorName.element?.enclosingElement,
      DotShorthandConstructorInvocation(:final element) =>
        element?.enclosingElement,
      _ => null,
    };
    return element is InterfaceElement &&
        _geometry.contains(element.name) &&
        _isFlutter(element.library.uri);
  }

  bool _isDimension(FormalParameterElement parameter) {
    if (!parameter.isNamed || !_dimensionNames.contains(parameter.name)) {
      return false;
    }
    final type = parameter.type;
    if (!type.isDartCoreDouble && !type.isDartCoreNum) return false;
    final uri = parameter.library?.uri;
    if (uri == null) return false;
    return _isFlutter(uri) ||
        (uri.isScheme('package') && uri.pathSegments.first == package);
  }

  static bool _isFlutter(Uri uri) =>
      uri.toString() == 'dart:ui' ||
      (uri.isScheme('package') && uri.pathSegments.first == 'flutter');

  /// The raw numbers [expression] is made of, or the variables that hide one.
  Iterable<AstNode> _rawNumbers(Expression expression, [int depth = 0]) sync* {
    if (depth > 8) return;
    switch (expression) {
      case IntegerLiteral(:final value) when value != 0:
        yield expression;
      case DoubleLiteral(:final value) when value != 0:
        yield expression;
      case ParenthesizedExpression(:final expression):
        yield* _rawNumbers(expression, depth + 1);
      case PrefixExpression(:final operator, :final operand)
          when operator.type == TokenType.MINUS:
        yield* _rawNumbers(operand, depth + 1);
      case BinaryExpression(
            :final operator,
            :final leftOperand,
            :final rightOperand,
          )
          when operator.type == TokenType.PLUS ||
              operator.type == TokenType.MINUS ||
              operator.type == TokenType.QUESTION_QUESTION:
        yield* _rawNumbers(leftOperand, depth + 1);
        yield* _rawNumbers(rightOperand, depth + 1);
      case ConditionalExpression(:final thenExpression, :final elseExpression):
        yield* _rawNumbers(thenExpression, depth + 1);
        yield* _rawNumbers(elseExpression, depth + 1);
      case SwitchExpression(:final cases):
        for (final branch in cases) {
          yield* _rawNumbers(branch.expression, depth + 1);
        }
      case Identifier():
        final initializer = _initializer(expression);
        if (initializer != null &&
            _rawNumbers(initializer, depth + 1).isNotEmpty) {
          yield expression;
        }
    }
  }

  /// The value behind a variable that is not one of the design tokens: a
  /// constant declared outside `lib/core/theme/`, or a local variable.
  Expression? _initializer(Identifier identifier) {
    var element = identifier.element;
    if (element is GetterElement) element = element.variable;
    if (element is! VariableElement) return null;
    if (element is FormalParameterElement) return null;
    if (element is LocalVariableElement) {
      return _localInitializer(identifier, element);
    }
    if (!element.isConst) return null;
    final source = element.library?.firstFragment.source.fullName ?? '';
    if (source.replaceAll(r'\', '/').contains(_themeDirectory)) return null;
    // ignore: deprecated_member_use
    return element.constantInitializer;
  }

  /// The initializer of the local [element], found in the outermost enclosing body.
  ///
  /// Not the innermost: a local declared outside a builder callback and used inside
  /// it — `final gap = 12.0; … builder: (c, _) => SizedBox(width: gap)` — was never
  /// found, and the number went unreported.
  static Expression? _localInitializer(
    Identifier use,
    LocalVariableElement element,
  ) {
    FunctionBody? body;
    for (AstNode? node = use; node != null; node = node.parent) {
      if (node is FunctionBody) body = node;
    }
    if (body == null) return null;
    final finder = _DeclarationFinder(element);
    body.accept(finder);
    return finder.initializer;
  }
}

class _DeclarationFinder extends RecursiveAstVisitor<void> {
  _DeclarationFinder(this.element);

  final LocalVariableElement element;

  Expression? initializer;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.declaredFragment?.element == element) {
      initializer = node.initializer;
    }
    super.visitVariableDeclaration(node);
  }
}
