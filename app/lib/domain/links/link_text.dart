/// Reading the links out of a text.
///
/// **Links are parsed from the text, not maintained by hand** — two truths would be one
/// too many. The server reads the same text to write the `link`
/// table; here it is read to draw the chips and fill the info bar. **Both sides check
/// against `golden/links.json`** — a link the device shows and the server does not
/// know is worse than none.
library;

import '../../core/common/app_names.dart';
import '../common/match_groups.dart';

// The prefixes of the normalized form.
const _keyPrefix = 'key:';
const _uriPrefix = 'uri:';

/// A link as it stands in the text — not yet resolved to an item.
sealed class LinkReference {
  const LinkReference();

  /// The normalized form from the golden file.
  String get normalized;
}

/// The typed form: `#TD-14`.
///
/// Convenient, but it requires the number to have been assigned already.
final class KeyReference extends LinkReference {
  const KeyReference(this.entityKey);

  final String entityKey;

  @override
  String get normalized => '$_keyPrefix$entityKey';

  @override
  bool operator ==(Object other) =>
      other is KeyReference && other.entityKey == entityKey;

  @override
  int get hashCode => entityKey.hashCode;
}

/// The form from the link picker: `hiwiski://todo/<uuid>`.
///
/// The reliable one — it also works for an item that was created offline and has no
/// number yet.
final class UriReference extends LinkReference {
  const UriReference(this.itemType, this.itemId);

  /// Upper case, like the entity type: the address `hiwiski://wiki_page/…` becomes
  /// `WIKI_PAGE`.
  final String itemType;

  final String itemId;

  @override
  String get normalized => '$_uriPrefix$itemType/$itemId';

  /// The address of an item — what the link picker inserts.
  ///
  /// The title with its brackets escaped: "Packing [summer]" ended the label at its
  /// own "]", and the link fell apart into stray text around a dead address.
  static String markdown(String itemType, String itemId, String title) =>
      '[${title.replaceAllMapped(_labelSpecial, (match) => '\\${match[0]}')}]'
      '(${UriSchemes.hiwiski}://${itemType.toLowerCase()}/$itemId)';

  static final _labelSpecial = RegExp(r'[\\\[\]]');

  @override
  bool operator ==(Object other) =>
      other is UriReference &&
      other.itemType == itemType &&
      other.itemId == itemId;

  @override
  int get hashCode => Object.hash(itemType, itemId);
}

/// The way back from the normalized form.
///
/// The Markdown parser only passes strings on to drawing; that is why a link travels
/// along as `key:TD-14` or `uri:TODO/<uuid>`.
LinkReference? referenceFromNormalized(String value) {
  if (value.startsWith(_keyPrefix)) {
    return KeyReference(value.substring(_keyPrefix.length));
  }
  if (value.startsWith(_uriPrefix)) {
    final rest = value.substring(_uriPrefix.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    return UriReference(rest.substring(0, slash), rest.substring(slash + 1));
  }
  return null;
}

/// A piece of text — either ordinary text or a link in it.
sealed class TextPart {
  const TextPart();
}

final class PlainPart extends TextPart {
  const PlainPart(this.text);

  final String text;
}

final class ReferencePart extends TextPart {
  const ReferencePart(this.reference, {required this.raw, this.label});

  final LinkReference reference;

  /// What stood in the text — `#TD-14` or the whole bracket.
  final String raw;

  /// The text between the brackets, if it was one.
  final String? label;

  /// What remains when the target is not here.
  ///
  /// For the typed form, the number as it stood. For the form from the picker, the
  /// title without brackets — the writer's words remain, but no chip promises a target
  /// that does not exist for this reader. A bare address without a title stays the
  /// address: swallowing it entirely would be worse.
  String get fallback => switch (reference) {
    KeyReference() => raw,
    UriReference() => switch (label) {
      final label? when label.isNotEmpty => label,
      _ => raw,
    },
  };
}

const String _uuid =
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';

/// Both notations in **one** pattern, in the order of the text.
///
/// Three alternatives, because the picker puts its address into a Markdown bracket: the
/// first swallows `[Title](hiwiski://…)` together with the bracket — otherwise the
/// brackets would remain next to the chip when drawn. The second takes the bare
/// address, the third the typed number.
///
/// **Upper case**, and with hyphen and digits: `#td-14` is text someone meant that way,
/// `# Einkauf` a heading and `#TD-` a beginning.
final RegExp linkPattern = RegExp(
  // The label may hold escaped characters — `\[`, `\]`, `\\` — as the picker writes a
  // title with brackets.
  '\\[((?:\\\\.|[^\\]\\n\\\\])*)\\]\\(hiwiski://([a-z_]+)/($_uuid)\\)'
  '|hiwiski://([a-z_]+)/($_uuid)'
  r'|#([A-Z][A-Z0-9]{0,7})-(\d+)',
);

/// Matches [linkPattern] at a position — in **linear time** over a whole text.
///
/// The labelled alternative scans from a `[` up to the next `]` or line break before it
/// can fail. Tried at every `[`, as `allMatches` and the Markdown parser do, a line of
/// `[` costs O(n²): 200,000 of them froze every reader for half a minute.
///
/// Every `[` up to where such a scan stopped stops at the **same** place, so it fails
/// the same way. The scanner remembers that place and does not try the pattern again
/// before it; the result is exactly that of the pattern.
class LinkScanner {
  String? _text;
  int _failsUntil = -1;

  /// The match of [linkPattern] that starts at [at] in [text], or `null`.
  Match? matchAt(String text, int at) {
    if (!identical(text, _text)) {
      _text = text;
      _failsUntil = -1;
    }
    final first = text.codeUnitAt(at);
    if (first != _openBracket && first != _hash && first != _h) return null;
    if (first == _openBracket && at < _failsUntil) return null;
    final match = linkPattern.matchAsPrefix(text, at);
    if (match == null && first == _openBracket) {
      _failsUntil = _labelStart.matchAsPrefix(text, at)?.end ?? at + 1;
    }
    return match;
  }

  /// All matches of [linkPattern] in [text], as `allMatches` would find them.
  Iterable<Match> allMatches(String text) sync* {
    int at = 0;
    while (at < text.length) {
      final match = matchAt(text, at);
      if (match == null) {
        at++;
      } else {
        yield match;
        at = match.end;
      }
    }
  }
}

/// The bracket and label of the first alternative — where its scan stops.
final _labelStart = RegExp(r'\[(?:\\.|[^\]\n\\])*');

final int _openBracket = '['.codeUnitAt(0);
final int _hash = '#'.codeUnitAt(0);
final int _h = 'h'.codeUnitAt(0);

/// The label of a `[label](hiwiski://…)` match, its escapes undone — `null` for the
/// other notations.
String? labelIn(Match match) =>
    match.group(1)?.replaceAllMapped(_escaped, (escape) => escape.groupOf(1));

final _escaped = RegExp(r'\\(.)');

/// The link behind a match of [linkPattern].
///
/// Takes a [Match] and not a [RegExpMatch], because the Markdown parser only hands out
/// a [Match] when drawing — and there should stay **one** place where the groups of
/// this pattern are read.
LinkReference? referenceIn(Match match) {
  if (match.group(3) != null) {
    return UriReference(
      match.groupOf(2).toUpperCase(),
      match.groupOf(3).toLowerCase(),
    );
  }
  if (match.group(5) != null) {
    return UriReference(
      match.groupOf(4).toUpperCase(),
      match.groupOf(5).toLowerCase(),
    );
  }
  if (match.group(6) != null) {
    return KeyReference('${match.group(6)}-${match.group(7)}');
  }
  return null;
}

/// All links of a text, in the order of the text and **without duplicates**.
///
/// The same link twice is one row: the table on the server has a unique index on it,
/// and the info bar should not show a target twice.
List<LinkReference> parseReferences(String? text) {
  if (text == null || text.trim().isEmpty) return const [];
  final found = <LinkReference>[];
  for (final match in LinkScanner().allMatches(text)) {
    final reference = referenceIn(match);
    if (reference != null && !found.contains(reference)) found.add(reference);
  }
  return found;
}

/// The same text, split into pieces — for drawing.
///
/// Here **with** duplicates: a link that appears twice in a sentence is drawn twice.
/// Only the table knows it once.
List<TextPart> splitReferences(String text) {
  if (text.isEmpty) return const [];
  final parts = <TextPart>[];
  int at = 0;
  for (final match in LinkScanner().allMatches(text)) {
    final reference = referenceIn(match);
    if (reference == null) continue;
    if (match.start > at) parts.add(PlainPart(text.substring(at, match.start)));
    parts.add(
      ReferencePart(reference, raw: match.groupOf(0), label: labelIn(match)),
    );
    at = match.end;
  }
  if (at < text.length) parts.add(PlainPart(text.substring(at)));
  return parts;
}
