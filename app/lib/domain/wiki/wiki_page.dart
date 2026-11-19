// The domain models of this feature, field for field what the local database
// stores. The repository maps its rows onto them: the layers above see these
// classes, never a Drift row.

import '../../core/common/page_properties.dart';

export '../../core/common/page_properties.dart';
export 'recipe_fields.dart';

/// A wiki page of any kind — a page, a folder, a recipe.
class WikiPage {
  const WikiPage({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    this.parentId,
    required this.position,
    required this.kind,
    this.entityKey,
    required this.title,
    required this.content,
    required this.tags,
    this.properties = emptyProperties,
    this.archivedAt,
    this.archivedBy,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String? parentId;
  final int position;
  final String kind;
  final String? entityKey;
  final String title;
  final String content;
  final String tags;

  /// What the page's kind adds beyond title and text — a recipe's servings,
  /// ingredients … — as the JSON object it is stored as. Read through the
  /// kind's accessors (`recipe_fields.dart`) or [property].
  final String properties;

  final DateTime? archivedAt;
  final String? archivedBy;

  /// The same page under another parent — for display only, the stored page keeps
  /// its own.
  WikiPage withParentId(String? parentId) => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    parentId: parentId,
    position: position,
    kind: kind,
    entityKey: entityKey,
    title: title,
    content: content,
    tags: tags,
    properties: properties,
    archivedAt: archivedAt,
    archivedBy: archivedBy,
  );

  /// One property as stored — `null` when the page has none of that name.
  Object? property(String name) => decodeProperties(properties)[name];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WikiPage &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.parentId == parentId &&
          other.position == position &&
          other.kind == kind &&
          other.entityKey == entityKey &&
          other.title == title &&
          other.content == content &&
          other.tags == tags &&
          other.properties == properties &&
          other.archivedAt == archivedAt &&
          other.archivedBy == archivedBy;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    parentId,
    position,
    kind,
    entityKey,
    title,
    content,
    tags,
    properties,
    archivedAt,
    archivedBy,
  ]);
}
