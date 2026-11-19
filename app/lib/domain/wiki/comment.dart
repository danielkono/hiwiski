// The domain models of this feature, field for field what the local database
// stores. The repository maps its rows onto them: the layers above see these
// classes, never a Drift row.

/// A comment on an item.
class Comment {
  const Comment({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.itemType,
    required this.itemId,
    required this.body,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String itemType;
  final String itemId;
  final String body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Comment &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.itemType == itemType &&
          other.itemId == itemId &&
          other.body == body;

  @override
  int get hashCode =>
      Object.hashAll([id, ownerId, version, deletedAt, itemType, itemId, body]);
}
