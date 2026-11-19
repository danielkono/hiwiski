import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

/// A change made on the device reaches the server only through the outbox.
///
/// The local database and the outbox must not drift apart: a synced row written
/// without its mutation is never synced — no error, no banner — and the next pulled
/// change to the item overwrites it. So outside the sync layer
/// (`core/sync/`) and the database itself (`core/db/`) nothing writes a synced table
/// with Drift; a change goes through `LocalWrites` (`core/sync/local_writes.dart`),
/// which writes the row and its outbox entry in one transaction.
///
/// Reported there:
///
/// - a Drift write — `into`, `update`, `delete`, the batch writes and the table's
///   own (`insertOne`, `deleteWhere`, …) — on a table that mixes in `SyncedItem`, or
///   on the outbox (`core/db/tables.dart`);
/// - a Drift write on a table whose static type does not say which table it is
///   (`TableInfo<Table, Object?>`): it could be a synced one;
/// - hand-written SQL that writes (`customStatement`, `customUpdate`, …, and the
///   executor's `runInsert` & co.): it names its tables in a string;
/// - `Outbox.add`: only `LocalWrites` queues a mutation, with its row;
/// - importing `core/sync/entity_codec.dart`: the codecs write the server's rows
///   without an outbox entry — that is the sync's job alone.
///
/// Tables that are not synced (the catalogue's mirror) stay writable. `test/` is
/// exempt.
class SyncedWrites extends MultiAnalysisRule {
  static const LintCode code = LintCode(
    'synced_writes',
    'A synced table is written only through LocalWrites.',
    correctionMessage:
        'Hand the row to a LocalWrite (core/sync/local_writes.dart): it writes the '
        'row and its outbox entry in one transaction.',
  );

  static const LintCode unknownTable = LintCode(
    'synced_writes',
    'This write does not say which table it goes to; it could be a synced one.',
    correctionMessage:
        'Write to the table itself (`_db.aisles`); a synced table is written '
        'through a LocalWrite (core/sync/local_writes.dart).',
    uniqueName: 'LintCode.synced_writes_unknown_table',
  );

  static const LintCode rawSql = LintCode(
    'synced_writes',
    'No hand-written SQL writes outside core/db and core/sync.',
    correctionMessage:
        'Write through Drift on the table itself, or through a LocalWrite for a '
        'synced table (core/sync/local_writes.dart).',
    uniqueName: 'LintCode.synced_writes_raw_sql',
  );

  static const LintCode outboxAdd = LintCode(
    'synced_writes',
    'Only LocalWrites puts mutations into the outbox.',
    correctionMessage:
        'Hand the row and its fields to a LocalWrite '
        '(core/sync/local_writes.dart): an outbox entry without its row, or a row '
        'without its entry, is how the two drift apart.',
    uniqueName: 'LintCode.synced_writes_outbox_add',
  );

  static const LintCode codecs = LintCode(
    'synced_writes',
    'The entity codecs belong to the sync.',
    correctionMessage:
        'They write rows without an outbox entry. A change made on the device goes '
        'through a LocalWrite (core/sync/local_writes.dart).',
    uniqueName: 'LintCode.synced_writes_codecs',
  );

  SyncedWrites()
    : super(
        name: 'synced_writes',
        description: 'Synced tables are written only through LocalWrites.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => const [
    code,
    unknownTable,
    rawSql,
    outboxAdd,
    codecs,
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
    if (!writesHere(own)) return;
    final visitor = _Visitor(this);
    registry.addMethodInvocation(this, visitor);
    registry.addImportDirective(this, visitor);
  }
}

/// Whether the file at [path] below `lib/` is held to the rule: everything but the
/// sync, the database and generated code.
bool writesHere(String path) =>
    !path.startsWith(_syncFolder) &&
    !path.startsWith(_dbFolder) &&
    !path.endsWith('.g.dart') &&
    !path.endsWith('.drift.dart') &&
    !path.endsWith('.freezed.dart');

const _syncFolder = 'core/sync/';
const _dbFolder = 'core/db/';
const _tables = 'core/db/tables.dart';
const _outbox = 'core/sync/outbox.dart';
const _codecs = 'core/sync/entity_codec.dart';

/// The table classes that must not be written past the outbox.
const _syncedMarkers = {'SyncedItem', 'OutboxEntries'};

/// The Drift classes whose writes take the table as their first argument: the
/// database (`into`, `update`, `delete`) and a batch. Not the statements they
/// return — `insert` and `replace` there take the row.
const _takingTable = {'DatabaseConnectionUser', 'Batch'};

/// Drift's writes that take the table as their first argument.
const _writesTakingTable = {
  'into',
  'update',
  'delete',
  'insert',
  'insertAll',
  'insertAllOnConflictUpdate',
  'insertFromSelect',
  'replace',
  'replaceAll',
  'deleteWhere',
  'deleteAll',
};

/// Drift's writes on the table itself (`TableStatements`).
const _writesOnTable = {
  'insert',
  'insertOne',
  'insertAll',
  'insertOnConflictUpdate',
  'insertReturning',
  'insertReturningOrNull',
  'update',
  'replaceOne',
  'delete',
  'deleteOne',
  'deleteWhere',
  'deleteAll',
};

/// Drift's writes in hand-written SQL.
const _rawWrites = {
  'customStatement',
  'customUpdate',
  'customInsert',
  'customWriteReturning',
  'runCustom',
  'runInsert',
  'runUpdate',
  'runDelete',
  'runBatched',
};

enum _Table { synced, plain, unknown }

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final MultiAnalysisRule rule;

  @override
  void visitImportDirective(ImportDirective node) {
    final library = node.libraryImport?.importedLibrary;
    if (library == null || !_inApp(library, _codecs)) return;
    rule.reportAtNode(node.uri, diagnosticCode: SyncedWrites.codecs);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (element is! ExecutableElement) return;
    final name = node.methodName.name;

    if (name == 'add' && _isOutbox(element.enclosingElement)) {
      rule.reportAtNode(
        node.methodName,
        diagnosticCode: SyncedWrites.outboxAdd,
      );
      return;
    }
    if (!_fromDrift(element)) return;
    if (_rawWrites.contains(name)) {
      rule.reportAtNode(node.methodName, diagnosticCode: SyncedWrites.rawSql);
      return;
    }

    final Expression? table;
    if (element.enclosingElement is ExtensionElement) {
      if (!_writesOnTable.contains(name)) return;
      table = node.realTarget;
    } else {
      if (!_takingTable.contains(element.enclosingElement?.name)) return;
      if (!_writesTakingTable.contains(name)) return;
      table = node.argumentList.arguments
          .where((argument) => argument is! NamedArgument)
          .firstOrNull
          ?.argumentExpression;
    }
    if (table == null) return;
    switch (_classify(table.staticType)) {
      case _Table.plain:
        return;
      case _Table.synced:
        rule.reportAtNode(node.methodName, diagnosticCode: SyncedWrites.code);
      case _Table.unknown:
        rule.reportAtNode(
          node.methodName,
          diagnosticCode: SyncedWrites.unknownTable,
        );
    }
  }

  /// A synced table, a table of the app's that is not synced, or a type that does
  /// not say.
  static _Table _classify(DartType? type, {int depth = 0}) {
    if (type is TypeParameterType) {
      return switch (_classify(type.bound, depth: depth)) {
        _Table.synced => _Table.synced,
        _ => _Table.unknown,
      };
    }
    if (type is! InterfaceType) return _Table.unknown;
    final classes = [
      type.element,
      for (final s in type.allSupertypes) s.element,
    ];
    if (classes.any(_isSyncedMarker)) return _Table.synced;
    // `TableInfo<T, D>` with a synced `T`.
    if (depth == 0 &&
        type.typeArguments.any(
          (argument) => _classify(argument, depth: 1) == _Table.synced,
        )) {
      return _Table.synced;
    }
    if (classes.any((element) => _inApp(element.library, _tables))) {
      return _Table.plain;
    }
    return _Table.unknown;
  }

  static bool _isSyncedMarker(InterfaceElement element) =>
      _syncedMarkers.contains(element.name) && _inApp(element.library, _tables);

  static bool _isOutbox(Element? element) =>
      element is ClassElement &&
      element.name == 'Outbox' &&
      _inApp(element.library, _outbox);

  static bool _fromDrift(Element element) {
    final uri = element.library?.uri;
    return uri != null &&
        uri.isScheme('package') &&
        uri.pathSegments.first == 'drift';
  }

  /// Whether [library] is the app's file at [path] below `lib/`.
  static bool _inApp(LibraryElement? library, String path) {
    final uri = library?.uri;
    if (uri == null || !uri.isScheme('package')) return false;
    return uri.pathSegments.skip(1).join('/') == path;
  }
}
