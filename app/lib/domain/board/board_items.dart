// The domain models of this feature, field for field what the local database
// stores. The repository maps its rows onto them: the layers above see these
// classes, never a Drift row.

/// A board: the start board or the dashboard.
class Board {
  const Board({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.kind,
    required this.name,
    required this.layout,
    required this.columns,
    this.token,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String kind;
  final String name;
  final String layout;
  final int columns;
  final String? token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Board &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.kind == kind &&
          other.name == name &&
          other.layout == layout &&
          other.columns == columns &&
          other.token == token;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    kind,
    name,
    layout,
    columns,
    token,
  ]);
}

/// A tile on a board.
class BoardWidget {
  const BoardWidget({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.boardId,
    required this.kind,
    required this.config,
    required this.gridX,
    required this.gridY,
    required this.gridW,
    required this.gridH,
    required this.position,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String boardId;
  final String kind;
  final String config;
  final int gridX;
  final int gridY;
  final int gridW;
  final int gridH;
  final int position;

  /// The same tile at another place and size on the grid.
  BoardWidget placedAt({
    required int x,
    required int y,
    required int width,
    required int height,
  }) => .new(
    id: id,
    ownerId: ownerId,
    version: version,
    deletedAt: deletedAt,
    boardId: boardId,
    kind: kind,
    config: config,
    gridX: x,
    gridY: y,
    gridW: width,
    gridH: height,
    position: position,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardWidget &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.boardId == boardId &&
          other.kind == kind &&
          other.config == config &&
          other.gridX == gridX &&
          other.gridY == gridY &&
          other.gridW == gridW &&
          other.gridH == gridH &&
          other.position == position;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    boardId,
    kind,
    config,
    gridX,
    gridY,
    gridW,
    gridH,
    position,
  ]);
}
