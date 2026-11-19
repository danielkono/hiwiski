import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Keeps every file of the app in its layer.
///
/// The layer follows from the folder:
///
/// | Layer | Folders below `lib/` |
/// | --- | --- |
/// | composition root | `main.dart`, `app/` |
/// | shared vocabulary | `core/common/` |
/// | generated API models | `core/api/generated/`, `core/api/hiwiski_failure.dart` |
/// | service | `core/api/`, `core/db/`, `core/sync/`, `core/storage/`, `core/platform/` |
/// | model | `data/` |
/// | domain | `domain/` |
/// | ViewModel | every `*_view_model.dart`; in `features/` and `components/` every file outside a `view/` folder |
/// | view | every `view/` folder, `core/ui/`, `core/shell/`, `core/theme/`, `core/l10n/`, `core/routing/` |
///
/// Dependencies point downwards only. Every layer may use the shared vocabulary and
/// the generated API models; beyond that:
///
/// - **view** → the ViewModel of its own screen or component (the ViewModel files in
///   the folder that holds its `view/` folder), other views, and `domain/` for the
///   types; never `data/`, never a service, never the composition root, never another
///   screen's ViewModel. The parts several ViewModels share (a file without the
///   `_view_model` suffix in a folder above) are part of their state: views below
///   that folder may import them. `core/ui/`, `core/theme/` and `core/l10n/` read no provider;
///   no view declares one.
/// - **ViewModel** → `data/`, `domain/`, the services, and the providers of the
///   composition root ([viewModelProviders]); never a view, never another ViewModel
///   (a `*_view_model.dart`). Parts several ViewModels of a feature share sit next to
///   them without the suffix.
/// - **model** → the services and `domain/`; a repository never imports another
///   area's repository.
/// - **domain** → only `domain/`.
/// - **service** → only services.
///
/// Nothing under `features/<x>/` imports from `features/<y>/`; components, `data/`,
/// `domain/` and core import no feature — except `core/routing/`, which leads to the
/// screens. Model, domain and services use neither Riverpod nor Flutter's widgets.
///
/// The composition root wires everything and may import anything. Everything under
/// `test/` is exempt. A file below `lib/` that sits in none of these folders is
/// reported as well: a file without a layer is a file without rules.
class LayerBoundaries extends MultiAnalysisRule {
  static const LintCode code = LintCode(
    'layer_boundaries',
    'The {0} layer must not import {1}.',
    correctionMessage:
        'Dependencies point downwards: view → its ViewModel → model and domain → '
        'services.',
  );

  static const LintCode unplaced = LintCode(
    'layer_boundaries',
    'This file sits in no layer folder.',
    correctionMessage:
        'Move it into a feature or component, into data/ or domain/, or into one '
        'of the folders below lib/core/.',
    uniqueName: 'LintCode.layer_boundaries_unplaced',
  );

  static const LintCode providerInView = LintCode(
    'layer_boundaries',
    'A view declares no provider.',
    correctionMessage: "Move the state into the screen's ViewModel.",
    uniqueName: 'LintCode.layer_boundaries_provider_in_view',
  );

  LayerBoundaries()
    : super(
        name: 'layer_boundaries',
        description: 'Every file stays in its layer.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => const [
    code,
    unplaced,
    providerInView,
  ];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (context.isInTestDirectory) return;
    final library = context.libraryElement?.uri;
    if (library == null || !library.isScheme('package')) return;
    final path = context.definingUnit.file.path.replaceAll(r'\', '/');
    final libIndex = path.lastIndexOf('/lib/');
    if (libIndex < 0) return;
    final own = path.substring(libIndex + '/lib/'.length);
    if (_generated(own)) return;
    final visitor = _Visitor(
      this,
      package: library.pathSegments.first,
      file: own,
    );
    registry.addCompilationUnit(this, visitor);
    registry.addImportDirective(this, visitor);
    registry.addExportDirective(this, visitor);
    if (layerOf(own) == Layer.view) registry.addAnnotation(this, visitor);
  }
}

bool _generated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.drift.dart') ||
    path.startsWith('core/l10n/generated/');

enum Layer {
  composition('composition root'),
  common('shared vocabulary'),
  models('generated API models'),
  service('service'),
  model('model'),
  domain('domain'),
  viewModel('ViewModel'),
  view('view');

  const Layer(this.label);

  final String label;
}

const _serviceFolders = [
  'core/api/',
  'core/db/',
  'core/sync/',
  'core/storage/',
  'core/platform/',
];

const _viewFolders = [
  'core/ui/',
  'core/shell/',
  'core/theme/',
  'core/l10n/',
  'core/routing/',
];

/// The view folders whose widgets read no provider: they are handed what they show.
const _passiveFolders = ['core/ui/', 'core/theme/', 'core/l10n/'];

/// The files of the composition root a ViewModel may import: the providers of the
/// repositories and stores and the composed link index — nothing else.
const viewModelProviders = {
  'app/repositories.dart',
  'app/stores.dart',
  'app/link_index.dart',
};

const _viewModelSuffix = '_view_model.dart';

/// The layer of a file, by its path below `lib/`; `null` if it has none.
Layer? layerOf(String path) {
  if (path == 'main.dart' || path.startsWith('app/')) return Layer.composition;
  if (path.startsWith('core/common/')) return Layer.common;
  if (path.startsWith('core/api/generated/') ||
      path == 'core/api/hiwiski_failure.dart') {
    return Layer.models;
  }
  if (_serviceFolders.any(path.startsWith)) return Layer.service;
  if (path.startsWith('data/')) return Layer.model;
  if (path.startsWith('domain/')) return Layer.domain;
  if (path.endsWith(_viewModelSuffix)) return Layer.viewModel;
  final folders = path.split('/')..removeLast();
  if (folders.contains('view') || _viewFolders.any(path.startsWith)) {
    return Layer.view;
  }
  // A feature's or component's ViewModels: everything outside its view/ folders.
  if (path.startsWith('features/') || path.startsWith('components/')) {
    return Layer.viewModel;
  }
  return null;
}

/// The area a file belongs to: `features/todo`, `components/tags`, `data/todo`,
/// `core/ui` …
String areaOf(String path) {
  final parts = path.split('/');
  return parts.length > 2 ? '${parts[0]}/${parts[1]}' : parts.first;
}

/// The folder whose ViewModel a view belongs to: the one holding its `view/` folder —
/// `features/todo/checklist` for `features/todo/checklist/view/row.dart`. In core,
/// the folder itself: the shell's view and ViewModel sit side by side.
String homeOf(String view) {
  final folders = view.split('/')..removeLast();
  final index = folders.lastIndexOf('view');
  return (index < 0 ? folders : folders.sublist(0, index)).join('/');
}

String _folderOf(String path) => (path.split('/')..removeLast()).join('/');

bool _isRepositoryFile(String path) =>
    path.startsWith('data/') && path.endsWith('_repository.dart');

/// Why [from] may not import [target] — or `null` if it may.
String? violation(String from, String target) {
  final source = layerOf(from);
  final layer = layerOf(target);
  if (source == null || layer == null) return null;
  if (source == Layer.composition) return null;
  if (layer == Layer.common || layer == Layer.models) return null;
  if (target.startsWith('features/') &&
      areaOf(target) != areaOf(from) &&
      !from.startsWith('core/routing/')) {
    return 'another feature';
  }
  if (layer == Layer.composition) {
    if (source == Layer.viewModel && viewModelProviders.contains(target)) {
      return null;
    }
    return 'the composition root';
  }
  switch (source) {
    case Layer.composition:
      return null;
    case Layer.common:
    case Layer.models:
      return 'the ${layer.label} layer';
    case Layer.service:
      return layer == Layer.service ? null : 'the ${layer.label} layer';
    case Layer.domain:
      return layer == Layer.domain ? null : 'the ${layer.label} layer';
    case Layer.model:
      if (layer == Layer.service || layer == Layer.domain) return null;
      if (layer != Layer.model) return 'the ${layer.label} layer';
      if (_isRepositoryFile(target) && areaOf(target) != areaOf(from)) {
        return "another area's repository";
      }
      return null;
    case Layer.viewModel:
      return switch (layer) {
        Layer.model || Layer.domain || Layer.service => null,
        Layer.viewModel when target.endsWith(_viewModelSuffix) =>
          'another ViewModel',
        Layer.viewModel => null,
        _ => 'the ${layer.label} layer',
      };
    case Layer.view:
      return switch (layer) {
        Layer.view || Layer.domain => null,
        Layer.viewModel when _folderOf(target) == homeOf(from) => null,
        // A type several screens' ViewModels share, beside them without the suffix,
        // is part of their state; it reaches their views.
        Layer.viewModel
            when !target.endsWith(_viewModelSuffix) &&
                areaOf(target) == areaOf(from) &&
                homeOf(from).startsWith('${_folderOf(target)}/') =>
          null,
        Layer.viewModel => "another screen's ViewModel",
        _ => 'the ${layer.label} layer',
      };
  }
}

/// What of Flutter the lower layers may use: no widgets, no rendering — they run
/// without a screen. An allow-list, not a list of the forbidden: matched by the last
/// segment, `package:flutter/src/widgets/framework.dart` slipped through.
const _flutterAllowed = {'foundation.dart', 'services.dart'};

const _headless = {
  Layer.common,
  Layer.models,
  Layer.service,
  Layer.model,
  Layer.domain,
};

String? _forbiddenPackage(String from, Layer source, Uri uri) {
  final package = uri.pathSegments.first;
  // Every Riverpod package — hooks_riverpod got through a list of three names.
  final riverpod = package.contains('riverpod');
  if (riverpod && _passiveFolders.any(from.startsWith)) return 'Riverpod';
  if (!_headless.contains(source)) return null;
  if (riverpod) return 'Riverpod';
  if (package == 'flutter' &&
      !(uri.pathSegments.length == 2 &&
          _flutterAllowed.contains(uri.pathSegments.last))) {
    return "Flutter's widgets";
  }
  return null;
}

/// The annotations that declare a provider.
const _providerAnnotations = {'riverpod', 'Riverpod'};

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, {required this.package, required this.file});

  final MultiAnalysisRule rule;
  final String package;

  /// The path of the file below `lib/`.
  final String file;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (layerOf(file) != null) return;
    final first = node.directives.firstOrNull ?? node.declarations.firstOrNull;
    if (first == null) return;
    rule.reportAtNode(first, diagnosticCode: LayerBoundaries.unplaced);
  }

  @override
  void visitAnnotation(Annotation node) {
    if (!_providerAnnotations.contains(node.name.name)) return;
    rule.reportAtNode(node, diagnosticCode: LayerBoundaries.providerInView);
  }

  @override
  void visitImportDirective(ImportDirective node) => _check(node);

  @override
  void visitExportDirective(ExportDirective node) => _check(node);

  void _check(NamespaceDirective node) {
    final source = layerOf(file);
    if (source == null) return;
    final uris = [
      node.uri,
      for (final configuration in node.configurations) configuration.uri,
    ];
    for (final literal in uris) {
      final value = literal.stringValue;
      if (value == null) continue;
      final uri = Uri.tryParse(value);
      if (uri == null || uri.isScheme('dart')) continue;
      if (uri.isScheme('package')) {
        if (uri.pathSegments.first != package) {
          final forbidden = _forbiddenPackage(file, source, uri);
          if (forbidden != null) {
            rule.reportAtNode(
              literal,
              arguments: [source.label, forbidden],
              diagnosticCode: LayerBoundaries.code,
            );
          }
          continue;
        }
        _report(literal, source, uri.pathSegments.skip(1).join('/'));
        continue;
      }
      _report(literal, source, _resolve(value));
    }
  }

  String _resolve(String relative) {
    final parts = file.split('/')..removeLast();
    for (final segment in relative.split('/')) {
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (segment != '.') {
        parts.add(segment);
      }
    }
    return parts.join('/');
  }

  void _report(StringLiteral literal, Layer source, String target) {
    final reason = violation(file, target);
    if (reason == null) return;
    rule.reportAtNode(
      literal,
      arguments: [source.label, reason],
      diagnosticCode: LayerBoundaries.code,
    );
  }
}
