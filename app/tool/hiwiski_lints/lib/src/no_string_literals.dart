import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

/// Reports every string literal that is not the value of a named constant.
///
/// A string that appears inline -- a map key, a route path, a preference key, a
/// widget key, a text -- is a value someone has to find by searching for it, and a
/// typo in a second copy of it is not a compile error. It belongs in a named
/// constant; UI text belongs in `app_*.arb`.
///
/// Allowed are:
/// - the initializer of a `const` variable, of any scope;
/// - the initializer of a top-level or `static final` variable -- for values that
///   cannot be `const`, such as a `RegExp` or a `Logger`;
/// - the arguments of an enum value;
/// - annotations (`@JsonKey(name: ...)`, `@TypedGoRoute(path: ...)`);
/// - URIs in directives (`import`, `export`, `part`);
/// - messages for developers: the positional arguments of an `Error` or
///   `Exception`, the message of an `assert`, log lines (`Logger`, `debugPrint`,
///   `dart:developer`'s `log`), `toString()` -- prose, not a value anyone looks up;
/// - strings without a single letter: `''`, `', '`, `'\n'`, `'$a/$b'` are
///   separators and formatting, not values;
/// - everything under `test/`: test data is data.
///
/// A closure inside such an initializer is code, not a constant: a literal in its
/// body is reported.
class NoStringLiterals extends AnalysisRule {
  static const LintCode code = LintCode(
    'no_string_literals',
    'String literal outside a named constant.',
    correctionMessage:
        'Move the string into a named constant, or use a localized string for '
        'UI text.',
  );

  NoStringLiterals()
    : super(
        name: 'no_string_literals',
        description: 'String literals belong in named constants.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    final visitor = _Visitor(this);
    registry.addSimpleStringLiteral(this, visitor);
    registry.addStringInterpolation(this, visitor);
    registry.addAdjacentStrings(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  static final _letter = RegExp(r'\p{L}', unicode: true);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.parent is AdjacentStrings) return;
    if (!_letter.hasMatch(node.value)) return;
    _check(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (node.parent is AdjacentStrings) return;
    final text = node.elements.whereType<InterpolationString>().map(
      (element) => element.value,
    );
    if (!text.any(_letter.hasMatch)) return;
    _check(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    if (!_letter.hasMatch(node.strings.map(_text).join())) return;
    _check(node);
  }

  void _check(StringLiteral node) {
    if (!_isConstant(node)) rule.reportAtNode(node);
  }

  static String _text(StringLiteral literal) => switch (literal) {
    SimpleStringLiteral(:final value) => value,
    StringInterpolation(:final elements) =>
      elements.whereType<InterpolationString>().map((e) => e.value).join(),
    AdjacentStrings(:final strings) => strings.map(_text).join(),
  };

  /// Whether [node] is the value of a named constant, or sits where Dart only
  /// accepts a constant that is itself a declaration.
  static bool _isConstant(StringLiteral node) {
    AstNode child = node;
    var insideCall = false;
    for (AstNode? current = node.parent; current != null;) {
      switch (current) {
        case Directive() || Annotation() || EnumConstantArguments():
          return true;
        case AssertStatement(:final message) ||
                AssertInitializer(:final message)
            when message == child:
          return true;
        // Only the call the literal is passed to directly: a key computed for a
        // message is still a key.
        case ArgumentList(:final parent) when !insideCall:
          if (child is! NamedArgument && _takesMessage(parent)) return true;
          insideCall = true;
        case FunctionBody(parent: MethodDeclaration(:final name))
            when name.lexeme == 'toString':
          return true;
        // A function body inside an initializer is code that runs later, not part
        // of the constant.
        case FunctionBody():
          return false;
        case VariableDeclaration(:final parent?)
            when parent is VariableDeclarationList:
          return parent.isConst || (parent.isFinal && _isStaticScope(parent));
      }
      child = current;
      current = current.parent;
    }
    return false;
  }

  /// Whether the positional arguments of [call] are a message for developers: a
  /// log line or the text of an exception.
  static bool _takesMessage(AstNode? call) {
    switch (call) {
      case InstanceCreationExpression(:final staticType?)
          when staticType is InterfaceType:
        return [staticType, ...staticType.allSupertypes].any(
          (type) =>
              type.element.library.isDartCore &&
              (type.element.name == 'Error' ||
                  type.element.name == 'Exception'),
        );
      case MethodInvocation(methodName: Identifier(:final element)) ||
          FunctionExpressionInvocation(function: Identifier(:final element)):
        if (element == null) return false;
        final library = element.library?.uri.toString() ?? '';
        return switch (element.enclosingElement) {
          InterfaceElement(:final name) =>
            name == 'Logger' && library.startsWith('package:logging/'),
          // `debugPrint` is a variable of function type, `log` a function.
          _ =>
            (element.name == 'debugPrint' &&
                    library.startsWith('package:flutter/')) ||
                (element.name == 'log' && library == 'dart:developer'),
        };
      default:
        return false;
    }
  }

  static bool _isStaticScope(VariableDeclarationList list) =>
      switch (list.parent) {
        TopLevelVariableDeclaration() => true,
        FieldDeclaration(:final isStatic) => isStatic,
        _ => false,
      };
}
