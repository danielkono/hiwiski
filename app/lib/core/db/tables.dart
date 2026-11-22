import 'package:drift/drift.dart';

import '../common/wire.dart';

/// The columns **every** synced item carries.
///
/// They are not reinvented per module. `version` comes from the
/// server and is **never incremented locally** — whoever increments it makes every
/// later change run into a conflict and only notices once someone was offline.
mixin SyncedItem on Table {
  TextColumn get id => text()();

  TextColumn get ownerId => text()();

  /// The state from the server. `0` as long as the item only exists locally.
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// Soft delete. Without a tombstone a device that was offline recreates the item on
  /// its next push.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TodoListRow')
class TodoLists extends Table with SyncedItem {
  TextColumn get name => text().withDefault(const Constant(''))();

  /// The readable key (`LST-3`). `null` as long as the list has only existed offline.
  TextColumn get entityKey => text().nullable()();

  /// What the list is for — free text below its name, links included.
  TextColumn get description => text().nullable()();

  /// `STANDARD`, `SHOPPING` or `KANBAN`. Cannot be changed after creation — except
  /// that a task list may become a board.
  TextColumn get kind =>
      text().withDefault(const Constant(ListKinds.standard))();

  /// A board's columns as JSON, in their order — see `KanbanColumn`. `null` on the
  /// other kinds.
  TextColumn get columns => text().nullable()();

  TextColumn get colorToken =>
      text().withDefault(const Constant(ColorTokens.blue))();

  IntColumn get position => integer().withDefault(const Constant(0))();

  /// Members and groups, comma-separated. Assignees may edit the list.
  TextColumn get assignees => text().withDefault(const Constant(''))();

  /// Tag IDs, comma-separated.
  TextColumn get tags => text().withDefault(const Constant(''))();

  /// Set while the list is archived — kept, read-only, out of the overview. Its tasks
  /// count as archived with it.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  TextColumn get archivedBy => text().nullable()();
}

@DataClassName('TodoRow')
class Todos extends Table with SyncedItem {
  TextColumn get listId => text()();

  /// The readable key. `null` as long as the item has only existed offline — the UI
  /// shows a dash there.
  TextColumn get entityKey => text().nullable()();

  TextColumn get title => text().withDefault(const Constant(''))();

  TextColumn get description => text().nullable()();

  TextColumn get status =>
      text().withDefault(const Constant(TodoStatuses.open))();

  /// On a board: the column the card stands in. Where it is shown is derived — a done
  /// card stands in the done column whatever this says (Kanban).
  TextColumn get columnId => text().nullable()();

  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Local time without a zone, `HH:mm`.
  TextColumn get dueTime => text().nullable()();

  TextColumn get rrule => text().nullable()();

  /// Members **and** groups, comma-separated.
  TextColumn get assignees => text().withDefault(const Constant(''))();

  /// Tag IDs, comma-separated.
  TextColumn get tags => text().withDefault(const Constant(''))();

  IntColumn get position => integer().withDefault(const Constant(0))();

  RealColumn get amount => real().nullable()();

  TextColumn get unit => text().nullable()();

  TextColumn get productId => text().nullable()();
}

@DataClassName('TodoOccurrenceRow')
class TodoOccurrences extends Table with SyncedItem {
  TextColumn get todoId => text()();

  DateTimeColumn get occurrenceDate => dateTime()();

  DateTimeColumn get doneAt => dateTime().nullable()();

  TextColumn get doneBy => text().nullable()();

  BoolColumn get skipped => boolean().withDefault(const Constant(false))();
}

/// The `state` of an outbox entry.
abstract final class OutboxStates {
  static const pending = 'pending';

  /// A prerequisite was rejected.
  static const blocked = 'blocked';
  static const rejected = 'rejected';

  /// Waits for a board that only arrives with the next sync; `errorCode` says which.
  static const parked = 'parked';
}

/// The local queue of changes not yet transmitted.
///
/// Every entry knows its prerequisite: tasks created offline in a list created
/// offline, a subpage under a new page. **If the first push fails permanently, the
/// dependent ones must not run**.
@DataClassName('OutboxRow')
class OutboxEntries extends Table {
  TextColumn get mutationId => text()();

  TextColumn get entityType => text()();

  TextColumn get entityId => text()();

  TextColumn get containerType => text().nullable()();

  TextColumn get containerId => text().nullable()();

  /// `upsert` or `delete`.
  TextColumn get op => text()();

  /// Only the changed fields, as JSON. Never whole objects.
  TextColumn get fields => text().withDefault(const Constant('{}'))();

  /// The state this mutation builds on. `null` for a new item.
  IntColumn get baseVersion => integer().nullable()();

  /// The `mutationId` that has to go through first.
  TextColumn get dependsOn => text().nullable()();

  /// `pending`, `blocked` (a prerequisite was rejected) or `rejected`.
  TextColumn get state =>
      text().withDefault(const Constant(OutboxStates.pending))();

  /// The error code for `rejected` — it appears in the visible list.
  TextColumn get errorCode => text().nullable()();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();

  /// A title for the list of what was rejected: "Plan vacation and 3 more changes
  /// could not be applied."
  TextColumn get label => text().nullable()();

  @override
  Set<Column> get primaryKey => {mutationId};
}

/// A conflict the user has not seen yet.
///
/// **A conflict is always shown**, on every screen.
@DataClassName('ConflictRow')
class Conflicts extends Table {
  TextColumn get id => text()();

  TextColumn get entityType => text()();

  TextColumn get entityId => text()();

  TextColumn get field => text()();

  /// The discarded local value, as JSON.
  TextColumn get mine => text().nullable()();

  /// The valid server value, as JSON.
  TextColumn get theirs => text().nullable()();

  /// What both sides started from, as JSON — `null` when the server no longer knows it.
  TextColumn get base => text().nullable()();

  DateTimeColumn get detectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// What sync remembers: state, instance identifier.
@DataClassName('SyncStateRow')
class SyncStates extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// The members, stored locally.
///
/// They go over REST and not through sync — they carry no owner and no sharing and so
/// are not items in the sense of the glossary. Without a server this
/// table is the family: the member made on the device, and in the demo the family
/// it shows.
@DataClassName('MemberRow')
class Members extends Table {
  TextColumn get id => text()();

  TextColumn get username => text()();

  TextColumn get displayName => text()();

  TextColumn get colorToken =>
      text().withDefault(const Constant(ColorTokens.slate))();

  BoolColumn get isAdmin => boolean().withDefault(const Constant(false))();

  TextColumn get avatarImageId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// --- Calendar -------------------------------------------------------------

@DataClassName('CalendarRow')
class Calendars extends Table with SyncedItem {
  TextColumn get name => text().withDefault(const Constant(''))();

  TextColumn get colorToken =>
      text().withDefault(const Constant(ColorTokens.blue))();

  /// `LOCAL` or `EXTERNAL`. An external one belongs to a subscription, is read-only and
  /// is **not** offered when creating an event — in an earlier version an orphaned external
  /// calendar then sat empty in the selection and accepted nothing there.
  TextColumn get kind =>
      text().withDefault(const Constant(CalendarKinds.local))();

  IntColumn get position => integer().withDefault(const Constant(0))();

  /// Tags that apply to every event in the calendar, comma-separated — added when
  /// filtering and showing, never copied onto the events.
  TextColumn get tags => text().withDefault(const Constant(''))();

  /// Minutes before the start, for every event without a reminder of its own — applied
  /// when scheduling and showing, never copied onto the events. `null`: no default.
  IntColumn get defaultReminderMinutes => integer().nullable()();
}

/// An event — with **three time forms side by side**, not in one shared column.
///
/// Each stores something different: `TIMED` an instant, `ALL_DAY`
/// a date (January 1 is not at 23:00 the day before in Portugal), `RECURRING` a local
/// time with a zone ("every Monday 8:00" stays 8:00, even across a clock change).
@DataClassName('EventRow')
class Events extends Table with SyncedItem {
  TextColumn get calendarId => text()();

  /// Imported events get none: they belong to the source, and a school holiday
  /// calendar would use up five hundred numbers for something nobody cites.
  TextColumn get entityKey => text().nullable()();

  TextColumn get title => text().withDefault(const Constant(''))();

  TextColumn get description => text().nullable()();

  TextColumn get location => text().nullable()();

  TextColumn get timeForm =>
      text().withDefault(const Constant(TimeForms.timed))();

  DateTimeColumn get startsAt => dateTime().nullable()();

  DateTimeColumn get endsAt => dateTime().nullable()();

  DateTimeColumn get startDate => dateTime().nullable()();

  DateTimeColumn get endDate => dateTime().nullable()();

  /// `2026-09-29T08:00` — without a zone, because that sits next to it.
  TextColumn get localStart => text().nullable()();

  TextColumn get localEnd => text().nullable()();

  TextColumn get timeZone => text().nullable()();

  TextColumn get rrule => text().nullable()();

  /// Cancelled and moved single occurrences, as a JSON object keyed by the
  /// **original** start — never by a running number.
  TextColumn get exceptions => text().withDefault(const Constant('{}'))();

  /// Comma-separated, as with tasks.
  TextColumn get attendees => text().withDefault(const Constant(''))();

  /// Tag IDs, comma-separated.
  TextColumn get tags => text().withDefault(const Constant(''))();

  IntColumn get reminderMinutes => integer().nullable()();

  /// On import, matching is by UID plus `RECURRENCE-ID`, never by title.
  TextColumn get sourceUid => text().nullable()();
}

@DataClassName('CalendarSubscriptionRow')
class CalendarSubscriptions extends Table with SyncedItem {
  TextColumn get calendarId => text()();

  TextColumn get name => text().withDefault(const Constant(''))();

  TextColumn get url => text().withDefault(const Constant(''))();

  /// `EVENT` or `TASK`. Fixed at creation and locked afterwards: everything already
  /// imported would otherwise be of the wrong type.
  TextColumn get targetKind =>
      text().withDefault(const Constant(SubscriptionTargets.event))();

  TextColumn get targetListId => text().nullable()();

  TextColumn get syncInterval =>
      text().withDefault(const Constant(SyncIntervals.daily))();

  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  /// Stored on the subscription instead of turning the fetch into a server error — the
  /// subscription stays, the error is noted on it.
  TextColumn get lastError => text().nullable()();

  IntColumn get importedCount => integer().withDefault(const Constant(0))();
}

/// An ICS link of one's own. Several per member.
@DataClassName('CalendarFeedRow')
class CalendarFeeds extends Table with SyncedItem {
  TextColumn get name => text().withDefault(const Constant(''))();

  /// Comma-separated.
  TextColumn get calendarIds => text().withDefault(const Constant(''))();

  /// `FULL` or `BUSY_ONLY`.
  TextColumn get contentMode =>
      text().withDefault(const Constant(FeedContentModes.full))();

  /// In **plain text**, unlike device tokens: the address has to be showable again at
  /// any time so it can be entered on a second device.
  TextColumn get token => text().withDefault(const Constant(''))();
}

// --- Wiki, recipes, catalog -----------------------------------------------

/// A wiki page — **nested arbitrarily deep**.
///
/// A page without a `parentId` is what used to be an area. `PAGE` and `RECIPE` are
/// **one table and one entity type**: a recipe is a page with extra fields, not a type
/// of its own — otherwise the tree would need two queries, moving two paths and
/// sharing two inheritance rules.
@DataClassName('WikiPageRow')
class WikiPages extends Table with SyncedItem {
  TextColumn get parentId => text().nullable()();

  IntColumn get position => integer().withDefault(const Constant(0))();

  /// `PAGE`, `RECIPE`, `RECIPE_FOLDER` — or a kind this app does not know yet.
  TextColumn get kind => text().withDefault(const Constant(PageKinds.page))();

  TextColumn get entityKey => text().nullable()();

  TextColumn get title => text().withDefault(const Constant(''))();

  /// Markdown — also when it is written formatted: the editor only draws it so.
  TextColumn get content => text().withDefault(const Constant(''))();

  /// Tag IDs, comma-separated.
  TextColumn get tags => text().withDefault(const Constant(''))();

  /// What the page's kind adds — a recipe's servings, ingredients, source, picture
  /// and time — as a JSON object, key by key as sync delivers it. A new
  /// kind's fields land here without a new column.
  TextColumn get properties => text().withDefault(const Constant('{}'))();

  /// Set while the page is archived. **Per page, not inherited**: a subpage left active
  /// under an archived page stays in the tree, under the nearest active ancestor.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  TextColumn get archivedBy => text().nullable()();
}

/// The product catalog — the **only domain entity without an owner and without
/// sharing**.
///
/// It grows with the input and belongs to everyone. Without a shared entry there would
/// be no telling that two recipes mean the same thing, and the shopping list would not
/// know which category "Quark" belongs in.
@DataClassName('ProductRow')
class Products extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  /// The category ([Aisles]) the shopping list groups it under; none is "Other".
  TextColumn get aisleId => text().nullable()();

  TextColumn get defaultUnit => text().nullable()();

  IntColumn get usageCount => integer().withDefault(const Constant(0))();

  /// Put into its category on this device while it had no server: the
  /// assignment goes to the server the device connects to. Never set otherwise —
  /// with a server every assignment is the server's at once.
  BoolColumn get assignedHere => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// An image added while the device had no server — the bytes
/// themselves: there is no server to fetch them from. Its carrier points to [id]
/// already; when the device connects, it is uploaded under that id and leaves this
/// table for the image cache.
@DataClassName('LocalImageRow')
class LocalImages extends Table {
  TextColumn get id => text()();

  /// `WIKI_PAGE`, `TODO_LIST`, `TODO`, `EVENT` or `MEMBER` — the upload's `ownerType`.
  TextColumn get ownerType => text()();

  TextColumn get ownerItemId => text()();

  TextColumn get filename => text()();

  BlobColumn get bytes => blob()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A category of the shopping list — like the catalog, without an owner
/// and without sharing, mirrored over REST.
///
/// Exactly one of [key] and [name] is set: a built-in category is shown in the app's
/// language, one of the family's own as written.
@DataClassName('AisleRow')
class Aisles extends Table {
  TextColumn get id => text()();

  TextColumn get key => text().nullable()();

  TextColumn get name => text().nullable()();

  /// The order in the shopping list, the same for the whole family.
  IntColumn get position => integer()();

  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A comment — on **all** items, not just wiki pages.
@DataClassName('CommentRow')
class Comments extends Table with SyncedItem {
  TextColumn get itemType => text()();

  TextColumn get itemId => text()();

  TextColumn get body => text().withDefault(const Constant(''))();
}

// --- Boards ----------------------------------------------------------------

/// **Exactly one start board and exactly one dashboard per member**.
///
/// Both are created on their own on first open — an empty screen with a "Create board"
/// button would be a question with only one answer.
@DataClassName('BoardRow')
class Boards extends Table with SyncedItem {
  /// `START` or `DASHBOARD`.
  TextColumn get kind => text().withDefault(const Constant(BoardKinds.start))();

  TextColumn get name => text().withDefault(const Constant(''))();

  /// `FLOW` (start, tiles of different heights) or `GRID` (dashboard, grid).
  TextColumn get layout =>
      text().withDefault(const Constant(BoardLayouts.flow))();

  IntColumn get columns => integer().withDefault(const Constant(4))();

  /// Dashboard only. In **plain text** like the ICS token: the address has to be
  /// showable again so it can be typed into the wall tablet.
  TextColumn get token => text().nullable()();
}

/// A tile.
///
/// **Both layout sets are on every tile** — `position` for `FLOW`, the four `grid*`
/// for `GRID` —, so a widget can move between boards without losing its layout.
@DataClassName('WidgetRow')
class Widgets extends Table with SyncedItem {
  TextColumn get boardId => text()();

  /// An **unknown** type shows a placeholder and never crashes. An installed app can
  /// be older than the server.
  TextColumn get kind => text()();

  /// JSON object, different per kind (widget catalog).
  TextColumn get config => text().withDefault(const Constant('{}'))();

  IntColumn get gridX => integer().withDefault(const Constant(0))();

  IntColumn get gridY => integer().withDefault(const Constant(0))();

  IntColumn get gridW => integer().withDefault(const Constant(1))();

  IntColumn get gridH => integer().withDefault(const Constant(1))();

  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// The column of an element's or a connection's text — `text`, as on the wire. The
/// getter is called `body`: a getter `text` would hide the column builder of the same
/// name.
const _textColumn = 'text';

/// An element on a mind map — an item of its own in its page, so that two people
/// changing different elements never collide and a conflict names the one both changed.
@DataClassName('MindmapNodeRow')
class MindmapNodes extends Table with SyncedItem {
  /// The page the map is on; its share is the element's.
  TextColumn get pageId => text()();

  /// `PLAIN`, `NOTE`, `IMAGE`, `LINK` — an unknown one is kept and drawn as a
  /// placeholder.
  TextColumn get kind =>
      text().withDefault(const Constant(MindmapKinds.plain))();

  IntColumn get x => integer().withDefault(const Constant(0))();

  IntColumn get y => integer().withDefault(const Constant(0))();

  IntColumn get width => integer().withDefault(const Constant(160))();

  IntColumn get height => integer().withDefault(const Constant(80))();

  /// The stacking order, higher above lower; a tie goes to the later id.
  RealColumn get layer => real().withDefault(const Constant(0))();

  TextColumn get body =>
      text().named(_textColumn).withDefault(const Constant(''))();

  /// What a link element points to, `hiwiski://<type>/<id>`.
  TextColumn get target => text().nullable()();

  /// What a link element shows of it: `TITLE` or `CONTENT`; `null` for the title.
  TextColumn get linkView => text().nullable()();

  /// An accent token or `#RRGGBB`; `null` for the theme's own.
  TextColumn get color => text().nullable()();

  TextColumn get shape => text().nullable()();

  TextColumn get textSize => text().nullable()();

  /// The colour of its text, as [color] is given; `null` for the theme's own.
  TextColumn get textColor => text().nullable()();

  /// A stroke drawn by hand: its points across the element, `x,y x,y …` from 0 to
  /// 10000 — and how thick it is drawn.
  TextColumn get points => text().nullable()();
  IntColumn get strokeWidth => integer().nullable()();

  /// Turned clockwise about its centre, in whole degrees 0–359; `null`: not turned.
  IntColumn get rotation => integer().nullable()();
}

/// A connection between two elements of the same mind map, drawn from centre to centre.
@DataClassName('MindmapEdgeRow')
class MindmapEdges extends Table with SyncedItem {
  TextColumn get pageId => text()();

  TextColumn get fromId => text()();

  TextColumn get toId => text()();

  /// The label at the middle of the line.
  TextColumn get body =>
      text().named(_textColumn).withDefault(const Constant(''))();

  TextColumn get color => text().nullable()();

  /// How thick the line is drawn; `null` for the app's own.
  IntColumn get strokeWidth => integer().nullable()();

  /// The line drawn ([MindmapLines]) and its arrow heads ([MindmapArrows]); `null`:
  /// solid, without heads.
  TextColumn get line => text().nullable()();
  TextColumn get arrows => text().nullable()();
}

/// A tag — an item of its own with owner and sharing.
///
/// The assignment is stored as a `tags` column on the items. An ID whose tag is not
/// here is skipped: the tag may not be seen, or it was deleted.
@DataClassName('TagRow')
class Tags extends Table with SyncedItem {
  TextColumn get name => text().withDefault(const Constant(''))();

  /// `RED`, `BLUE`, `AMBER`, `VIOLET`, `GREEN`, `PINK`.
  TextColumn get colorToken =>
      text().withDefault(const Constant(ColorTokens.blue))();
}

/// A member's own order of the task lists on the overview — one row per member, its
/// id the member's id. A list's `position` is the family's; this is a preference.
@DataClassName('ListOrderRow')
class ListOrders extends Table with SyncedItem {
  /// The list ids in the member's order, as JSON; lists missing here follow by their
  /// position.
  TextColumn get listIds => text().withDefault(const Constant('[]'))();
}

/// What a backup restore left behind on this device: a row it had and the restored
/// server has not, or has older. Not a synced table — the device's
/// own copy, kept until it is brought back or let go.
@DataClassName('LeftBehindRow')
class LeftBehindItems extends Table {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get ownerId => text()();

  /// The row's version on this device — newer than what the server kept.
  IntColumn get version => integer()();

  /// Deleted on this device after the backup: what goes back is the deletion.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  TextColumn get containerId => text().nullable()();
  TextColumn get entityKey => text().nullable()();

  /// Every field, as JSON — as `EntityCodec.stored` read the row.
  TextColumn get fields => text().withDefault(const Constant('{}'))();
  TextColumn get label => text().withDefault(const Constant(''))();
  DateTimeColumn get leftAt => dateTime()();

  /// Compared with the restored server's state. Until then it is only a copy of the
  /// mirror taken before the mirror went, and shown to nobody.
  BoolColumn get settled => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {entityType, entityId};
}
