import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

import 'layer_boundaries.dart';

/// A ViewModel that loads builds its state asynchronously, and the view shows it with
/// `when`.
///
/// - **No loading flag in a state**: a `…State` class holds no `loading` or
///   `isLoading` field — that is the `AsyncValue` the ViewModel's `build()` returns.
/// - **`when` keeps the data on a reload**: every emission of a watched stream
///   rebuilds an async ViewModel, its state is "loading" with the old value for a
///   moment. Riverpod's `when` shows `loading` then — the page would flash on every
///   tick. A view calls it with `skipLoadingOnReload: true`.
/// - **No `isLoading` in a view**, for the same reason: the strip would flash.
/// - **No shared helpers that watch**: under `features/` and `components/`, a
///   top-level function taking a `Ref` sits in a `*_view_model.dart` — each
///   ViewModel puts its state together itself.
///
/// `test/` is exempt.
class AsyncState extends MultiAnalysisRule {
  static const LintCode loadingField = LintCode(
    'async_state',
    'A state holds no loading flag.',
    correctionMessage:
        "Return Future<XState> from the ViewModel's build(); the view switches "
        'with when.',
  );

  static const LintCode whenWithoutSkip = LintCode(
    'async_state',
    'when shows loading on every rebuild of the ViewModel.',
    correctionMessage: 'Pass skipLoadingOnReload: true.',
    uniqueName: 'LintCode.async_state_when',
  );

  static const LintCode isLoadingInView = LintCode(
    'async_state',
    'isLoading flashes on every rebuild of the ViewModel.',
    correctionMessage: 'Show the loading state in the loading branch of when.',
    uniqueName: 'LintCode.async_state_is_loading',
  );

  static const LintCode sharedHelper = LintCode(
    'async_state',
    'A function that watches belongs to one ViewModel.',
    correctionMessage:
        'Put it, private, into the *_view_model.dart that uses it; shared rules '
        'go into domain/ as pure functions.',
    uniqueName: 'LintCode.async_state_shared_helper',
  );

  AsyncState()
    : super(
        name: 'async_state',
        description: 'ViewModels build their state asynchronously.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => const [
    loadingField,
    whenWithoutSkip,
    isLoadingInView,
    sharedHelper,
  ];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    final path = context.definingUnit.file.path.replaceAll(r'\', '/');
    final libIndex = path.lastIndexOf('/lib/');
    if (libIndex < 0) return;
    final own = path.substring(libIndex + '/lib/'.length);
    if (own.endsWith('.g.dart') || own.contains('/generated/')) return;
    final layer = layerOf(own);
    final visitor = _Visitor(this, own, layer);
    if (layer == Layer.view) {
      registry.addMethodInvocation(this, visitor);
      registry.addPrefixedIdentifier(this, visitor);
      registry.addPropertyAccess(this, visitor);
    }
    if (layer == Layer.viewModel) {
      registry.addClassDeclaration(this, visitor);
      registry.addFunctionDeclaration(this, visitor);
    }
  }
}

const _asyncValues = {'AsyncValue', 'AsyncData', 'AsyncLoading', 'AsyncError'};

const _loadingFields = {'loading', 'isLoading'};

bool _isRiverpod(Uri? library) =>
    library != null &&
    library.isScheme('package') &&
    library.pathSegments.first.contains('riverpod');

bool _isAsyncValue(DartType? type) =>
    type is InterfaceType &&
    _asyncValues.contains(type.element.name) &&
    _isRiverpod(type.element.library.uri);

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.file, this.layer);

  final MultiAnalysisRule rule;

  /// The path of the file below `lib/`.
  final String file;
  final Layer? layer;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'when') return;
    if (!_isAsyncValue(node.realTarget?.staticType)) return;
    final skips = node.argumentList.arguments.any(
      (argument) =>
          argument is NamedArgument &&
          argument.name.lexeme == 'skipLoadingOnReload' &&
          argument.argumentExpression is BooleanLiteral &&
          (argument.argumentExpression as BooleanLiteral).value,
    );
    if (skips) return;
    rule.reportAtNode(
      node.methodName,
      diagnosticCode: AsyncState.whenWithoutSkip,
    );
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name != 'isLoading') return;
    if (!_isAsyncValue(node.prefix.staticType)) return;
    rule.reportAtNode(
      node.identifier,
      diagnosticCode: AsyncState.isLoadingInView,
    );
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name != 'isLoading') return;
    if (!_isAsyncValue(node.realTarget.staticType)) return;
    rule.reportAtNode(
      node.propertyName,
      diagnosticCode: AsyncState.isLoadingInView,
    );
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (!node.namePart.typeName.lexeme.endsWith('State')) return;
    final body = node.body;
    if (body is! BlockClassBody) return;
    for (final member in body.members) {
      if (member is! FieldDeclaration || member.isStatic) continue;
      for (final variable in member.fields.variables) {
        if (!_loadingFields.contains(variable.name.lexeme)) continue;
        rule.reportAtToken(
          variable.name,
          diagnosticCode: AsyncState.loadingField,
        );
      }
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (file.endsWith('_view_model.dart')) return;
    if (!file.startsWith('features/') && !file.startsWith('components/')) {
      return;
    }
    if (node.parent is! CompilationUnit) return;
    final parameters = node.functionExpression.parameters?.parameters ?? [];
    final takesRef = parameters.any((parameter) {
      final element = parameter.declaredFragment?.element.type.element;
      return element?.name == 'Ref' && _isRiverpod(element?.library?.uri);
    });
    if (!takesRef) return;
    rule.reportAtToken(node.name, diagnosticCode: AsyncState.sharedHelper);
  }
}
