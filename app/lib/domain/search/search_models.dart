import '../../core/api/generated/export.dart';

/// A hit as the UI needs it.
///
/// A class of its own and not the generated type: the local half delivers the same
/// fields but knows neither `SearchHit` nor the API. A shared type keeps both halves in
/// the same shape — and that is exactly what the spec demands: "**Both halves must
/// answer the same question the same way.**"
class SearchHitView {
  const SearchHitView({
    required this.itemType,
    required this.itemId,
    required this.title,
    this.entityKey,
    this.context,
    this.snippet,
    this.archived = false,
  });

  final String itemType;
  final String itemId;
  final String title;

  /// `TD-14` — the quotable number.
  final String? entityKey;

  /// The location: "Recipes › Autumn cooking", "Calendar Mama".
  final String? context;

  /// The snippet. Highlighting happens when drawing — the client knows its font sizes,
  /// and HTML would have to go through an app that renders none.
  final String? snippet;

  /// In the archive — only there when the search asked for it, or on a jump.
  final bool archived;

  static SearchHitView fromApi(SearchHit hit) => .new(
    itemType: hit.itemType,
    itemId: hit.itemId,
    title: hit.title,
    entityKey: hit.entityKey,
    context: hit.context,
    snippet: hit.snippet,
    archived: hit.archived ?? false,
  );
}

/// The result of a search — including **where** it comes from.
class const SearchOutcome({
  required final List<SearchHitView> hits,

  /// Searched on the device, not on the server.
  ///
  /// The UI says so: an empty result then means "not found here" and not
  /// "does not exist".
  required final bool offline,

  /// **An entered number jumps straight there** instead of being searched as full text.
  final SearchHitView? jumpTo,
});

/// The places in the text where the search term occurs.
///
/// The highlight is drawn via `TextStyle.background` and not as a
/// `WidgetSpan`, because a snippet has to be able to wrap in the middle of a sentence.
List<(int, int)> highlightRanges(String text, String term) {
  if (term.trim().isEmpty) return const [];
  final haystack = text.toLowerCase();
  // Some letters change length when lowercased ("İ" becomes two code units): the
  // offsets would then not fit the original, shifted or past its end — and
  // `substring` threw while the row was built. No highlight is better.
  if (haystack.length != text.length) return const [];
  final needle = term.trim().toLowerCase();
  final ranges = <(int, int)>[];
  int from = 0;
  while (true) {
    final at = haystack.indexOf(needle, from);
    if (at < 0) break;
    ranges.add((at, at + needle.length));
    from = at + needle.length;
  }
  return ranges;
}
