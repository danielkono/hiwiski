import '../../core/common/wire.dart';

/// How an element's words read — for a search, and for the lists that name it.
enum PinboardWords {
  /// Its text as it is written.
  text,

  /// Its text is Markdown: read without it.
  markdown,

  /// It has none: a picture is its picture, a stroke its line.
  none,

  /// Its text and the title of what it points to — a link's target, a member's name.
  target,
}

/// What the map's rules need to know about an element of a kind: what it is drawn
/// on, what can be chosen for it, how it is resized, how its words read.
///
/// One entry per kind ([pinboardKindOf]), which the rules and the choices offered for
/// a selected element ask instead of naming kinds. A new kind is described here, drawn
/// by its look (`PinboardElementView.lookOf`) and placed and edited by its tool on the
/// map's screen (docs/development/pinboard.md).
final class const PinboardKind({
  /// Drawn on a surface of its own, filled and outlined — not on the canvas itself.
  final bool surface = false,

  /// Given a colour: its surface's, a member's ring's, a stroke's.
  final bool coloured = false,

  /// Shows text whose colour and size can be chosen.
  final bool texted = false,

  /// Its outline can be chosen ([PinboardShapes]).
  final bool outlined = false,

  /// Its text has room around it to stand in ([PinboardTextAligns]).
  final bool placesText = false,

  /// A line whose thickness can be chosen.
  final bool stroked = false,

  /// Keeps its shape when resized: a picture its own, a member's circle its
  /// roundness.
  final bool keepsShape = false,

  /// A new one is as large as the last of its kind placed or resized on the map —
  /// a row of pictures or notes comes out alike. A snippet is as large as its words.
  final bool remembersSize = false,

  /// What it holds can be changed; a stroke is drawn again instead.
  final bool editable = true,

  /// It can be connected to another; a stroke is part of the picture, not a thought.
  final bool connectable = true,

  /// How its words read for a search and in lists.
  final PinboardWords words = .text,
});

/// What an element of [kind] is. A kind this app does not know — placed by a newer
/// one — is kept as it is and drawn as a placeholder on a surface; it is only moved,
/// coloured, connected and taken away.
PinboardKind pinboardKindOf(String kind) => _kinds[kind] ?? _unknown;

/// Whether this app knows [kind].
bool knowsPinboardKind(String kind) => _kinds.containsKey(kind);

/// Every kind this app knows.
Iterable<String> get pinboardKinds => _kinds.keys;

const _kinds = <String, PinboardKind>{
  PinboardKinds.plain: PinboardKind(texted: true),
  PinboardKinds.note: PinboardKind(
    surface: true,
    coloured: true,
    texted: true,
    outlined: true,
    placesText: true,
    remembersSize: true,
    words: .markdown,
  ),
  PinboardKinds.image: PinboardKind(
    keepsShape: true,
    remembersSize: true,
    words: .none,
  ),
  PinboardKinds.link: PinboardKind(
    surface: true,
    coloured: true,
    texted: true,
    outlined: true,
    remembersSize: true,
    words: .target,
  ),
  PinboardKinds.member: PinboardKind(
    coloured: true,
    keepsShape: true,
    remembersSize: true,
    words: .target,
  ),
  PinboardKinds.calendar: PinboardKind(
    surface: true,
    coloured: true,
    texted: true,
    outlined: true,
    remembersSize: true,
    words: .none,
  ),
  PinboardKinds.drawing: PinboardKind(
    coloured: true,
    stroked: true,
    editable: false,
    connectable: false,
    words: .none,
  ),
};

const _unknown = PinboardKind(surface: true, coloured: true, editable: false);
