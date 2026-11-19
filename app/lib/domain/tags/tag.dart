// The domain models of this feature, field for field what the local database
// stores. The repository maps its rows onto them: the layers above see these
// classes, never a Drift row.

/// A tag with its color.
class Tag {
  const Tag({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.name,
    required this.colorToken,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String name;
  final String colorToken;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.name == name &&
          other.colorToken == colorToken;

  @override
  int get hashCode =>
      Object.hashAll([id, ownerId, version, deletedAt, name, colorToken]);
}

/// The tag ids of an item, as a list.
List<String> tagIdsOf(String raw) =>
    raw.split(',').where((id) => id.isNotEmpty).toList();

/// The six colors of a tag.
const tagColorTokens = <String>[
  'RED',
  'BLUE',
  'AMBER',
  'VIOLET',
  'GREEN',
  'PINK',
];

/// The tag filters.
abstract final class TagFilterAreas {
  /// Calendar, tasks and wiki share one: "Work" picked in the calendar holds in the
  /// wiki too. Whether it survives switching between them is the device's choice
  /// (Account → Customize).
  static const areas = 'areas';

  /// The search has its own: it narrows one query, not the day.
  static const search = 'search';

  static const all = [areas, search];
}

/// Whether an item with these tags passes the filter: it has to carry **one** of the
/// selected ones.
bool passesTagFilter(Set<String> filter, String rawTags) =>
    filter.isEmpty || tagIdsOf(rawTags).any(filter.contains);

/// The tags in the order that matters to this member: **often and lately used** first.
///
/// Every use counts, a recent one more than an old one — so a tag used every day stays
/// ahead of one used once yesterday, and one nobody touched for months sinks. Never
/// used ones follow by name.
List<Tag> rankTags(List<Tag> tags, List<String> uses) {
  final score = <String, double>{};
  for (int i = 0; i < uses.length; i++) {
    score[uses[i]] = (score[uses[i]] ?? 0) + 1 / (1 + i / 10);
  }
  return [...tags]..sort((a, b) {
    final byScore = (score[b.id] ?? 0).compareTo(score[a.id] ?? 0);
    return byScore != 0
        ? byScore
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}
