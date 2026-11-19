import 'package:flutter/services.dart';

import '../common/match_groups.dart';
import 'link_index.dart';
import 'link_text.dart';

/// The `#…` being typed right before the cursor — what the completion works on.
class const ReferenceQuery({
  /// Where the `#` sits and where the cursor is: the range the choice replaces.
  required final int start,
  required final int end,

  /// What follows the `#`: `TD`, `TD-1`, `rout`.
  required final String text,
});

/// A `#` followed by at least one character, up to the cursor — at the start of the text
/// or after a space or an opening bracket. `# Heading` (a space after it) is Markdown,
/// not a reference, and `C#` is not one either.
final _token = RegExp(r'(?:^|[\s(\[])#([\p{L}\p{N}-]{1,30})$', unicode: true);

ReferenceQuery? referenceQueryAt(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final before = value.text.substring(0, selection.baseOffset);
  final match = _token.firstMatch(before);
  if (match == null) return null;
  final text = match.groupOf(1);
  return ReferenceQuery(
    start: selection.baseOffset - text.length - 1,
    end: selection.baseOffset,
    text: text,
  );
}

/// What fits the query: by number first (`#TD` → TD-14, TD-13 …, the newest first), then
/// by title (`#rout` → *Router*). At most [limit].
///
/// Archived items only by their exact number: whoever types `#TD-14` in full means that
/// one, archived or not; anyone merely typing along gets what is current.
List<LinkItem> completeReference(
  List<LinkItem> items,
  String query, {
  int limit = 6,
}) {
  final needle = query.toLowerCase();
  items = [
    for (final item in items)
      if (!item.archived || item.entityKey?.toLowerCase() == needle) item,
  ];
  int number(LinkItem item) =>
      int.tryParse(item.entityKey?.split('-').last ?? '') ?? 0;

  final byKey =
      items
          .where(
            (item) => item.entityKey?.toLowerCase().startsWith(needle) ?? false,
          )
          .toList()
        ..sort((a, b) => number(b).compareTo(number(a)));
  final byTitle =
      items
          .where(
            (item) =>
                !byKey.contains(item) &&
                item.title.toLowerCase().contains(needle),
          )
          .toList()
        ..sort((a, b) {
          // Titles that start with it before titles that merely contain it.
          final aStarts = a.title.toLowerCase().startsWith(needle) ? 0 : 1;
          final bStarts = b.title.toLowerCase().startsWith(needle) ? 0 : 1;
          return aStarts != bStarts
              ? aStarts - bStarts
              : a.title.compareTo(b.title);
        });
  return [...byKey, ...byTitle].take(limit).toList();
}

/// What a choice puts into the text: `#TD-14` — or, for an item created offline that has
/// no number yet, its address, which works just the same.
String referenceInsertion(LinkItem item) => item.entityKey != null
    ? '#${item.entityKey} '
    : '${UriReference.markdown(item.itemType, item.itemId, item.title)} ';

/// The text with the query replaced by the choice, the cursor right behind it.
TextEditingValue applyReference(
  TextEditingValue value,
  ReferenceQuery query,
  LinkItem item,
) {
  final insertion = referenceInsertion(item);
  final text = value.text.replaceRange(query.start, query.end, insertion);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: query.start + insertion.length),
  );
}
