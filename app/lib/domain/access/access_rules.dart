import '../../core/api/generated/export.dart';
import '../../core/common/wire.dart';

/// Changing the item: title, text, tags, deleting — *write* only.
bool mayWrite(AccessLevel? level) => level == null || level == .write;

/// Whether *check off* means anything on this type — only where something can be
/// ticked: lists and their tasks. On a calendar or a page the level would be *read*
/// under another name.
bool checkApplies(String itemType) =>
    itemType == EntityTypes.todoList || itemType == EntityTypes.todo;

/// Whether [me] owns the item [ownerId] names — `true` while nobody is known yet.
///
/// Deleting or moving a container (a list, a calendar, a shared page) and changing a
/// list's assignees are its owner's: that changes who sees what, which *write* does
/// not allow. The server refuses them for everyone else; offered
/// anyway, the change vanished and came back with an error.
bool ownsItem(String ownerId, String? me) => me == null || ownerId == me;

/// Toggling a task's done state — *check off* and *write*.
bool mayCheck(AccessLevel? level) => level != .read;
