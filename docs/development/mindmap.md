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
   `hiwiski_database.dart` and its line in `test/core/schema_upgrade_test.dart`, and
   its line in `mindmapNodeColumns` or `mindmapEdgeColumns`
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
forgotten anywhere on the way fails there, by its name.

## A value of a field

A new shape, a new place for a note's text, a new kind of line: its constant in
`wire.dart`, its name for people in the ARB files, and where it is drawn. The server
takes any name in capitals for these fields, and an older app draws a value it does
not know as the field's default — the constants' class says which.
