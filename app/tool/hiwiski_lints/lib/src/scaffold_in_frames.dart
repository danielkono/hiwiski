import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Reports every `Scaffold` built outside the app's frames.
///
/// A screen inside the shell is a `HiwiskiPage`: it brings the loading strip, the
/// header, the sync banner, the filter bar and the FAB. A screen that builds its own
/// `Scaffold` has opted out of all of that, and the next one copies it.
///
/// The frames are the only places that build one:
///
/// | File below `lib/` | Frame of |
/// | --- | --- |
/// | `core/shell/app_shell.dart` | the shell — navigation, and the root for snackbars |
/// | `core/ui/hiwiski_page.dart` | every screen inside the shell |
/// | `core/ui/auth_scaffold.dart` | the screens before sign-in |
/// | `features/board/kiosk/view/kiosk_screen.dart` | the board on the wall tablet |
/// | `features/wiki/pinboard/view/pinboard_screen.dart` | a pinboard full screen: the canvas runs under the header and the bars |
///
/// A new frame is added here on purpose, not by accident. `test/` is exempt.
class ScaffoldInFrames extends AnalysisRule {
  static const LintCode code = LintCode(
    'scaffold_in_frames',
    'A Scaffold outside the frames of the app.',
    correctionMessage:
        'Build the screen as a HiwiskiPage; a new frame of its own goes into '
        'the list of scaffold_in_frames.',
  );

  ScaffoldInFrames()
    : super(
        name: 'scaffold_in_frames',
        description: 'Only the frames of the app build a Scaffold.',
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
    final libIndex = path.lastIndexOf('/lib/');
    if (libIndex < 0) return;
    if (frames.contains(path.substring(libIndex + '/lib/'.length))) return;
    registry.addInstanceCreationExpression(this, _Visitor(this));
  }
}

/// The files below `lib/` that may build a `Scaffold`.
const frames = {
  'core/shell/app_shell.dart',
  'core/ui/hiwiski_page.dart',
  'core/ui/auth_scaffold.dart',
  'features/board/kiosk/view/kiosk_screen.dart',
  'features/wiki/pinboard/view/pinboard_screen.dart',
};

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final element = node.constructorName.type.element;
    if (element?.name != 'Scaffold') return;
    final library = element?.library?.uri;
    if (library == null || !library.isScheme('package')) return;
    if (library.pathSegments.first != 'flutter') return;
    rule.reportAtNode(node.constructorName);
  }
}
