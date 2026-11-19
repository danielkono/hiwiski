import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

/// A ViewModel answers the view through its state, not through return values.
///
/// The view watches the state and calls commands; a command changes the state or
/// the Model and returns nothing. A public method that hands data back — "how many
/// subpages", "the revision", "did it fit" — lets the view pull data past the state
/// and decide on it, and the flow it starts ends up in the view.
///
/// So every public method of a `…ViewModel` other than `build` returns `void` or
/// `Future<void>`. What the view needs belongs into the state; a flow that needs
/// the user (a confirmation) runs in the ViewModel and takes the question as a
/// callback.
///
/// A method that changes something may answer with its result — the id of what it
/// created, what to show, whether it fit — when it says so: `@command`
/// (`core/common/command.dart`). The view runs it through a Riverpod `Mutation`.
///
/// Getters are `avoid_public_notifier_properties`' business. `test/` is exempt.
class ViewModelCommands extends AnalysisRule {
  static const LintCode code = LintCode(
    'view_model_commands',
    "A ViewModel's command returns nothing; the view reads the state.",
    correctionMessage:
        'Put what the view needs into the state. A method that changes '
        'something and answers with its result is marked @command '
        '.',
  );

  ViewModelCommands()
    : super(
        name: 'view_model_commands',
        description: 'ViewModel methods are commands without a result.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    registry.addClassDeclaration(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.declaredFragment?.element.name ?? '';
    if (!name.endsWith('ViewModel')) return;
    final body = node.body;
    if (body is! BlockClassBody) return;
    for (final member in body.members) {
      if (member is! MethodDeclaration) continue;
      if (member.isStatic || member.isGetter || member.isSetter) continue;
      if (member.isOperator) continue;
      final methodName = member.name.lexeme;
      if (methodName.startsWith('_') || methodName == 'build') continue;
      final type = member.declaredFragment?.element.returnType;
      if (type == null || _isNothing(type)) continue;
      if (_isCommand(member)) continue;
      rule.reportAtToken(member.name);
    }
  }

  /// Annotated `@command` from the app's `core/common/command.dart`.
  static bool _isCommand(MethodDeclaration method) => method.metadata.any((a) {
    final element = a.elementAnnotation?.element;
    return a.name.name == 'command' &&
        (element?.library?.uri.path.endsWith('core/common/command.dart') ??
            false);
  });

  /// `void`, `Future<void>` and `FutureOr<void>`.
  static bool _isNothing(DartType type) {
    if (type is VoidType) return true;
    if (type is InterfaceType &&
        (type.isDartAsyncFuture || type.isDartAsyncFutureOr)) {
      return type.typeArguments.single is VoidType;
    }
    return false;
  }
}
