# The mind map

A page of the kind `MINDMAP` keeps its elements (`mindmap_node`) and connections
(`mindmap_edge`) as items of their own, whose container is the page
([wiki-page-kinds.md](wiki-page-kinds.md), "A kind with items of its own"). This page
says where things go when the map grows: a field, a value, an element kind.

## A field of an element or a connection

Every synced field goes by its name on the wire, from the contract to the screen. An
element's fields are in `MindmapNode.fields`, a connection's in `MindmapEdge.fields`,
and what goes over every field goes over that map: reading a row, storing what the
sync brings, writing a change, bringing an element back, telling two versions apart,
this device's version in a conflict, "Undo" and "Redo". A new field is added in these
places and nowhere else:

1. **The contract**: the field in `MindmapNodeFields` or `MindmapEdgeFields`
   (`api/components/wiki.yaml`) — optional, and described with what an app that
   does not know it shows. Then `./gradlew :api:updateBundledSpec` in `server/` and
   the client generated again ([api.md](api.md)).
2. **The server**: its column in a new Flyway migration — a released one is never
   edited —, its `SyncField` in `MindmapSyncTypes`, and, for a name in capitals or a
   number with bounds, its check in the type's `refusal`; a test in `MindmapIT`.
3. **The device's database**: its column in `MindmapNodes` or `MindmapEdges`
   (`lib/core/db/tables.dart`), a schema step with `_addColumnOnce` in
   `hiwiski_database.dart` and its line in `test/core/schema_upgrade_test.dart` and in
   the element of `test/core/stored_item_test.dart`, which sends every field back out;
   and its line in `mindmapNodeColumns` or `mindmapEdgeColumns`
   (`lib/core/db/synced_columns.dart`), which maps the field to its column for the
   sync codec and the repository alike.
4. **The domain**: its name in `WireFields` and, for named values, a class of
   constants in `lib/core/common/wire.dart` that says what an unknown one is drawn as;
   its property on `MindmapNode` or `MindmapEdge`, its line in `fields` and its line in
   `fromFields` (`lib/domain/wiki/mindmap.dart`) — next to each other.
5. **Its name**: in the history (`historyFieldLabel`) and, where its value means
   something to read in a conflict, in `mindmap_conflict_bar.dart`.
6. **The screen**: it is set with `MindmapViewModel.setFields(node, {field: value})`
   — `setFieldsOfAll` for a group, `setEdgeFields` for a connection — and drawn where
   the element is drawn. "Undo", "Redo", the sync and conflicts come with it.

`test/mindmap_fields_test.dart` takes the fields from the contract and follows each one
through all of that: stored and read, sent again whole, two versions told apart,
changed and taken back, this device's in a conflict, named in the history. A field
forgotten anywhere on the way fails there, by its name. On the server,
`MindmapIT.everyFieldTheContractNamesIsKeptAndHandedOn` does the same with the
contract's generated classes: every field is kept and handed to the next device.

## A value of a field

A new shape, a new place for a note's text, a new kind of line: its constant in
`wire.dart`, its name for people in the ARB files, and where it is drawn. The server
takes any name in capitals for these fields, and an older app draws a value it does
not know as the field's default — the constants' class says which.

## An element kind

An element's `kind` is a name in capitals (`MindmapKinds`); the server takes any, and
an app that does not know one keeps it and draws a placeholder that is only moved,
coloured, connected and taken away. A kind is described once for each part of the
app:

1. **What it is** — `lib/domain/wiki/mindmap_kinds.dart`: its `MindmapKind`, which
   says whether it is drawn on a surface of its own, takes a colour, shows text with
   a colour and size, has an outline to choose, room to place its text, a line to
   thicken; whether it keeps its shape when resized, takes the size of the last of
   its kind, can be edited and connected; and how its words read for a search and in
   lists. The rules and the choices offered for a selected element ask this, so a new
   kind is offered what its description allows without naming it anywhere else.
2. **How it is drawn** — `MindmapElementView.lookOf`
   (`lib/features/wiki/view/mindmap/mindmap_element.dart`): its symbol, what a screen
   reader says for it, and the widget that shows it — on the canvas, on the page's
   preview and in the map saved as a picture alike.
3. **How it is made and changed** — `_kindTools` on the map's screen
   (`lib/features/wiki/mindmap/view/mindmap_screen.dart`): its entry on the "Add"
   menu, what is asked for a new one and its size, what is asked to change it, and
   what a tap does where the map is read.

What it holds goes into the fields an element already has — `text` for words or a
picture, `target` for what it points to (`hiwiski://<type>/<id>`) — and into fields of
its own where it needs more ("A field of an element or a connection" above). The
choices for a selected element are plain data (`MindmapCornerOption`): the corner
draws them, and another way to offer them would draw the same list.

`test/mindmap_kinds_test.dart` checks that every kind the app knows is drawn as
itself; `mindmap_screen_test.dart` that every kind but a stroke is on the "Add" menu.

A kind that is a view of an item elsewhere in the app — a list, a page — may not need
to be a kind at all: a link element points to any item the link index knows and shows
its content as its preview does (`MindmapLinkContent`). A new kind is for what a
link's preview cannot show. The week of calendars (`CALENDAR`) is one: several
calendars at once, in a week of its own (`week`, or the current one for whoever
looks), with fields of its own for both. Its view is a component,
`lib/components/calendar_week/`, which shows what the calendar shows — a calendar
the reader cannot see is not on their device, and its events show nowhere.

## An outline

An element with a surface — a note, a link — is drawn in an outline (`shape`,
`MindmapShapes`); an unknown one is a rounded rectangle. An outline is described in
two places:

1. **Its geometry** — `lib/domain/wiki/mindmap_shapes.dart`: its `MindmapShape`, how
   far a connection reaches from the element's middle towards it, how wide it is at a
   height (the lines of a note that follows its shape), and the same outline a margin
   inside it.
2. **Its look** — `MindmapElementView.shapeLookOf`: its name, its border, and the room
   between it and the largest box of text inside it.

The outline sheet offers every outline there is (`mindmapShapes`), in that order, and
a conflict names them by their look; `test/mindmap_kinds_test.dart` checks that each
is drawn and named as itself. What an outline is drawn with — a border's colour and
thickness — are fields of the element, read where its border is drawn
(`MindmapElementView.build`).

## A pen option

The pen draws strokes, elements of the kind `DRAWING`, with what it is set to on the
map's screen — its colour, its thickness, the shape it draws. A new option is a field
of the element (above), its setting next to the others on the screen with its choice
in the pen's menu, and its value in the fields `MindmapViewModel.draw` is given. The
stroke being drawn and the stroke drawn are both painted by `paintStroke`, so what the
option changes in the drawing is changed there once.

## The choices and the tools

The corner shows what can be added, drawn and done with a selection; each choice is
plain data (`MindmapCornerOption`: a key, a symbol, a name, what a tap does), built by
the screen from what the selection's kind allows. Another way to offer them — a bar,
a panel — draws the same lists.

## The demo's map

The demo has a mind map (`app/assets/demo/demo-<lang>.json`, the page whose entry has
`mindmap`): its elements in the order they lie on each other, each with its kind, box,
`text` and `look` — fields by their names on the wire — and its connections by the
`key`s of their ends. What an element shows is named in the sample data's own words:
`image` a picture in `app/assets/demo/images/` (without its location and camera data),
`target` a page or list by `page:<key>` or `list:<key>`, `member` a member by their
place in the family, `points` a stroke on the map — with `pen`, the two corners of a
shape the pen draws. `Demo` places them as the map's screen does; a new kind or field
can be shown there, and `demo_seed_test.dart` checks that every element arrives.
