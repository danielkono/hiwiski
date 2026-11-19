import '../../core/common/wire.dart';

/// An item of the family's data — a task, a list, an event, a page … — by its type and
/// id.
///
/// The type is not derived from the id: the server keys history, sharing and comments
/// by both, the item need not be on this device, and whoever shows it knows its type.
class ItemRef {
  /// [type] as the wire names it ([EntityTypes]) — for what arrives from the server.
  const ItemRef(this.type, this.id);

  const ItemRef.todo(this.id) : type = EntityTypes.todo;

  const ItemRef.todoList(this.id) : type = EntityTypes.todoList;

  const ItemRef.event(this.id) : type = EntityTypes.event;

  const ItemRef.calendar(this.id) : type = EntityTypes.calendar;

  const ItemRef.wikiPage(this.id) : type = EntityTypes.wikiPage;

  final String type;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ItemRef && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => '$type/$id';
}
