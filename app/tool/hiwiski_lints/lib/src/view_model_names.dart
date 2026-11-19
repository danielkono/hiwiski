import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// One name for one thing: a screen's or component's state holder is a ViewModel,
/// never a controller or a notifier.
///
/// - **Every provider class is a ViewModel**: a class annotated `@riverpod` or
///   extending a Riverpod notifier is called `…ViewModel` and sits in a
///   `*_view_model.dart`.
/// - **A ViewModel file is named after its folder**: in `features/` and
///   `components/`, the folder `x/` holds `x_view_model.dart` — or, where the folder
///   name alone says too little, `<feature>_x_view_model.dart`
///   (`features/todo/overview/todo_overview_view_model.dart`).
/// - **A ViewModel's own state class ends in `State`**: when `build()` returns a
///   class declared in the same file, that class is called `…State`.
///
/// The composition root (`main.dart`, `app/`) holds the providers of the Model and
/// is exempt, as is everything under `test/`.
class ViewModelNames extends MultiAnalysisRule {
  static const LintCode providerClass = LintCode(
    'view_model_names',
    'A provider class is a ViewModel: name it …ViewModel in a *_view_model.dart.',
    correctionMessage:
        'Rename the class and its file; there are no controllers or notifiers '
        'beside the ViewModels.',
  );

  static const LintCode fileName = LintCode(
    'view_model_names',
    'A ViewModel file is named after its folder: {0}.',
    correctionMessage:
        'Rename the file, or the folder, so that the screen, its ViewModel and '
        'its folder share one name.',
    uniqueName: 'LintCode.view_model_names_file',
  );

  static const LintCode stateName = LintCode(
    'view_model_names',
    "A ViewModel's state class ends in State.",
    correctionMessage: 'Rename it to {0}.',
    uniqueName: 'LintCode.view_model_names_state',
  );

  ViewModelNames()
    : super(
        name: 'view_model_names',
        description:
            'ViewModels, their files and their states are named alike.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => const [
    providerClass,
    fileName,
    stateName,
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
    if (own == 'main.dart' || own.startsWith('app/')) return;
    if (own.endsWith('.g.dart') || own.contains('/generated/')) return;
    final visitor = _Visitor(this, own);
    registry.addCompilationUnit(this, visitor);
    registry.addClassDeclaration(this, visitor);
  }
}

const _viewModelSuffix = '_view_model.dart';

/// The names a ViewModel file below `lib/` may have — empty if any name will do.
List<String> allowedViewModelFiles(String path) {
  final parts = path.split('/');
  if (parts.first != 'features' && parts.first != 'components') return const [];
  if (parts.length < 3) return const [];
  final folder = parts[parts.length - 2];
  final feature = parts[1];
  return [
    '$folder$_viewModelSuffix',
    if (parts.first == 'features' && folder != feature)
      '${feature}_$folder$_viewModelSuffix',
  ];
}

const _providerAnnotations = {'riverpod', 'Riverpod'};

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.file);

  final MultiAnalysisRule rule;

  /// The path of the file below `lib/`.
  final String file;

  /// The classes declared in this file.
  final _declared = <String>{};

  @override
  void visitCompilationUnit(CompilationUnit node) {
    for (final declaration in node.declarations) {
      if (declaration is ClassDeclaration) {
        _declared.add(declaration.namePart.typeName.lexeme);
      }
    }
    if (!file.endsWith(_viewModelSuffix)) return;
    final allowed = allowedViewModelFiles(file);
    if (allowed.isEmpty || allowed.contains(file.split('/').last)) return;
    final first = node.directives.firstOrNull ?? node.declarations.firstOrNull;
    if (first == null) return;
    rule.reportAtNode(
      first,
      arguments: [allowed.join(' or ')],
      diagnosticCode: ViewModelNames.fileName,
    );
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (!_isProviderClass(node)) return;
    final name = node.namePart.typeName;
    if (!name.lexeme.endsWith('ViewModel') ||
        !file.endsWith(_viewModelSuffix)) {
      rule.reportAtToken(name, diagnosticCode: ViewModelNames.providerClass);
      return;
    }
    final body = node.body;
    if (body is! BlockClassBody) return;
    for (final member in body.members) {
      if (member is! MethodDeclaration || member.name.lexeme != 'build') {
        continue;
      }
      final type = member.returnType;
      if (type is! NamedType) return;
      final state = type.name.lexeme;
      if (!_declared.contains(state) || state.endsWith('State')) return;
      final expected = name.lexeme.replaceFirst(RegExp(r'ViewModel$'), 'State');
      rule.reportAtNode(
        type,
        arguments: [expected],
        diagnosticCode: ViewModelNames.stateName,
      );
    }
  }

  bool _isProviderClass(ClassDeclaration node) {
    if (node.metadata.any((a) => _providerAnnotations.contains(a.name.name))) {
      return true;
    }
    // Riverpod's notifiers — not its widgets (`ConsumerWidget`).
    final superclass = node.extendsClause?.superclass.element;
    final library = superclass?.library?.uri;
    return superclass?.name?.endsWith('Notifier') == true &&
        library != null &&
        library.isScheme('package') &&
        library.pathSegments.first.contains('riverpod');
  }
}
