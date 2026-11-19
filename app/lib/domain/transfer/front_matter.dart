/// The YAML block at the top of an exported file: what the item is beyond its text.
///
/// The field names are the ones the database and a backup use (`color_token`,
/// `due_date`), so one vocabulary describes an item wherever it is written down.
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

/// The names of the fields in a file's front matter.
abstract final class TransferFields {
  static const type = 'type';
  static const name = 'name';
  static const title = 'title';
  static const kind = 'kind';
  static const colorToken = 'color_token';
  static const tags = 'tags';
  static const columns = 'columns';
  static const position = 'position';
  static const properties = 'properties';

  // A task's own, below its line.
  static const dueDate = 'due_date';
  static const dueTime = 'due_time';
  static const rrule = 'rrule';
  static const amount = 'amount';
  static const unit = 'unit';

  // A board's column, as the list stores it.
  static const columnName = 'name';
  static const columnColorToken = 'colorToken';
  static const columnDone = 'done';
}

/// The `type` of a file: the table its item lives in.
abstract final class TransferTypes {
  static const todoList = 'todo_list';
  static const wikiPage = 'wiki_page';
}

const _fence = '---';

/// [fields] as a front matter block, ready to be followed by the text. Fields that
/// are `null` are left out.
String writeFrontMatter(Map<String, Object?> fields) {
  final out = StringBuffer()..writeln(_fence);
  _writeMap(out, {
    for (final MapEntry(:key, :value) in fields.entries) key: ?value,
  }, 0);
  out.writeln(_fence);
  return out.toString();
}

/// A file's text cut into its front matter and what follows. A file without one —
/// or with one that is not a YAML mapping — is all text: a note written by hand
/// imports as it is.
({Map<String, Object?> fields, String body}) splitFrontMatter(String text) {
  final normalized = text
      .replaceAll(_carriageReturnLineFeed, '\n')
      .replaceFirst(_byteOrderMark, '');
  final nothing = (fields: const <String, Object?>{}, body: normalized);
  final lines = normalized.split('\n');
  if (lines.firstOrNull?.trimRight() != _fence) return nothing;
  final end = lines.indexWhere((line) => line.trimRight() == _fence, 1);
  if (end < 0) return nothing;
  try {
    final decoded = loadYaml(lines.sublist(1, end).join('\n'));
    if (decoded is! YamlMap) return nothing;
    // Through JSON: plain maps and lists, and a mapping with a key that is not a
    // string is refused instead of carried along.
    final fields = jsonDecode(jsonEncode(decoded));
    if (fields is! Map<String, Object?>) return nothing;
    final body = lines.sublist(end + 1).join('\n');
    return (fields: fields, body: body.replaceFirst(_leadingBlankLines, ''));
  } on Object {
    // Not YAML after all — `---` also opens a text with a rule on its first line.
    return nothing;
  }
}

/// A field that is a list of texts — a single text counts as a list of one, the way
/// `tags: Home` is written by hand.
List<String> stringList(Object? value) => switch (value) {
  final List<Object?> list => [
    for (final element in list)
      if (element != null && '$element'.trim().isNotEmpty) '$element'.trim(),
  ],
  final String text when text.trim().isNotEmpty => [text.trim()],
  _ => const [],
};

const _carriageReturnLineFeed = '\r\n';
const _byteOrderMark = '\u{FEFF}';
final _leadingBlankLines = RegExp(r'^\n+');

const _indent = '  ';

void _writeMap(StringBuffer out, Map<String, Object?> map, int depth) {
  final pad = _indent * depth;
  for (final MapEntry(:key, :value) in map.entries) {
    final name = _plain.hasMatch(key) ? key : jsonEncode(key);
    switch (value) {
      case final Map<String, Object?> nested when nested.isNotEmpty:
        out.writeln('$pad$name:');
        _writeMap(out, nested, depth + 1);
      case final List<Object?> list when list.isNotEmpty:
        out.writeln('$pad$name:');
        for (final element in list) {
          out.writeln('$pad$_indent- ${_flow(element)}');
        }
      default:
        out.writeln('$pad$name: ${_flow(value)}');
    }
  }
}

/// A value on one line. Maps and lists in YAML's flow style, which is JSON with a
/// space after every colon and comma.
String _flow(Object? value) => switch (value) {
  null => _null,
  final String text => _scalar(text),
  final num number => _number(number),
  final bool flag => '$flag',
  final List<Object?> list => '[${list.map(_flow).join(', ')}]',
  final Map<String, Object?> map =>
    '{${map.entries.map((entry) => '${jsonEncode(entry.key)}: ${_flow(entry.value)}').join(', ')}}',
  _ => jsonEncode('$value'),
};

String _number(num number) =>
    number is double && number == number.roundToDouble() && number.isFinite
    ? '${number.toInt()}'
    : '$number';

/// A text without quotes only where YAML reads it back as that same text: letters
/// first, nothing a parser gives a meaning to, and none of the words it turns into a
/// boolean or nothing. Everything else is quoted the way JSON quotes — which YAML
/// reads as well.
String _scalar(String text) =>
    _plain.hasMatch(text) && !_reserved.contains(text.toLowerCase())
    ? text
    : jsonEncode(text);

const _null = 'null';
final _plain = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
const _reserved = {'true', 'false', 'null', 'yes', 'no', 'on', 'off', 'y', 'n'};
