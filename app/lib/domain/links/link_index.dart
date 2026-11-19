import 'link_text.dart';

/// An item that can be the target or source of a link.
///
/// Only what a chip and an info bar row need: icon via the type, **current** title,
/// mono number — plus the text its own links come from.
class LinkItem {
  const LinkItem({
    required this.itemType,
    required this.itemId,
    required this.title,
    this.entityKey,
    this.text,
    this.containerId,
    this.archived = false,
  });

  final String itemType;
  final String itemId;
  final String title;

  /// `TD-14`. `null` as long as the item has only existed offline.
  final String? entityKey;

  /// Description, note or Markdown — what the links are parsed from.
  final String? text;

  /// List, calendar or parent page. Jumping to a task needs its list: its route lives
  /// under the list, and a detour through the database would be a second path to the
  /// same piece of information.
  final String? containerId;

  /// In the archive. A link to it still resolves — a chip must not turn
  /// back into plain text because its target was put away — but the picker and the `#`
  /// suggestions do not offer it.
  final bool archived;

  String get _address => '$itemType/$itemId';
}

/// The references of each text, kept from one index to the next.
///
/// The index is built again whenever anything linkable changes — and nearly every text
/// is the one it was last time. Parsing all of them again was most of the work: on a
/// phone with 2.5 MB of wiki, a third of a second for one ticked-off task.
///
/// Keyed by the text itself, so an edited text is simply a new key; a text that is gone
/// drops out at the end of the round that no longer asked for it.
class ReferenceCache {
  var _current = <String, List<LinkReference>>{};
  var _next = <String, List<LinkReference>>{};

  /// The references in [text], parsed once.
  List<LinkReference> of(String? text) {
    if (text == null || text.isEmpty) return const [];
    return _next[text] ??= _current[text] ?? parseReferences(text);
  }

  /// One index is built: what it did not ask for is forgotten.
  void endRound() {
    _current = _next;
    _next = {};
  }
}

/// Text on an item that is not the item's own — a comment on it. Its links count as the
/// item's: a task linked in a comment on a page shows in the page's info bar, and the
/// page in the task's.
class const AttachedText({
  required final String itemType,
  required final String itemId,
  required final String text,
});

/// All links, derived from what lives on the device.
///
/// **Derived, not queried.** Everything except images, revisions and history is
/// mirrored, and links live in the text of the mirrored items — so they are not a
/// truth of their own that would need catching up, but a reading. That has three
/// consequences, all of them wanted: the info bar works **offline**, a chip shows the
/// new title right away on rename, and **what the reader may not see drops out by
/// itself** — it is not on their device at all.
class LinkIndex {
  LinkIndex._(
    this._byAddress,
    this._byKey,
    this._outgoing,
    this._incoming,
    this.items,
  );

  factory LinkIndex.from(
    List<LinkItem> items, {
    List<AttachedText> attached = const [],
    ReferenceCache? references,
  }) {
    final parse = references?.of ?? parseReferences;
    final byAddress = <String, LinkItem>{};
    final byKey = <String, LinkItem>{};
    for (final item in items) {
      byAddress[item._address] = item;
      if (item.entityKey case final key?) byKey[key] = item;
    }

    // Every text with the item it speaks for: its own, then what is attached to it.
    // An attachment on something not here — a comment on a calendar — has no row to
    // show up in.
    final texts = <(LinkItem, String?)>[
      for (final item in items) (item, item.text),
      for (final text in attached)
        if (byAddress['${text.itemType}/${text.itemId}'] case final item?)
          (item, text.text),
    ];

    final outgoing = <String, List<LinkItem>>{};
    final incoming = <String, List<LinkItem>>{};
    // The same target in the description and in a comment is one row.
    final seen = <String, Set<String>>{};
    for (final (item, text) in texts) {
      final references = parse(text);
      if (references.isEmpty) continue;
      final address = item._address;
      for (final reference in references) {
        final target = switch (reference) {
          KeyReference(:final entityKey) => byKey[entityKey],
          UriReference(:final itemType, :final itemId) =>
            byAddress['$itemType/$itemId'],
        };
        // A link to something that is not here is not a link: it stays plain text
        // when rendered, and it does not appear in the info bar.
        if (target == null) continue;
        final targetAddress = target._address;
        if (targetAddress == address) continue;
        if (!(seen[address] ??= <String>{}).add(targetAddress)) continue;
        (outgoing[address] ??= <LinkItem>[]).add(target);
        (incoming[targetAddress] ??= <LinkItem>[]).add(item);
      }
    }
    references?.endRound();
    return LinkIndex._(byAddress, byKey, outgoing, incoming, items);
  }

  final Map<String, LinkItem> _byAddress;
  final Map<String, LinkItem> _byKey;
  final Map<String, List<LinkItem>> _outgoing;
  final Map<String, List<LinkItem>> _incoming;

  /// Everything linkable — the selection in the link sheet reads from it. Archived items
  /// included; whoever offers a choice leaves them out ([LinkItem.archived]).
  final List<LinkItem> items;

  /// The item behind a link, or `null`.
  LinkItem? resolve(LinkReference reference) => switch (reference) {
    KeyReference(:final entityKey) => _byKey[entityKey],
    UriReference(:final itemType, :final itemId) =>
      _byAddress['$itemType/$itemId'],
  };

  /// Where this item points to.
  List<LinkItem> outgoing(String itemType, String itemId) =>
      _outgoing['$itemType/$itemId'] ?? const [];

  /// Who points to this item.
  List<LinkItem> incoming(String itemType, String itemId) =>
      _incoming['$itemType/$itemId'] ?? const [];
}
