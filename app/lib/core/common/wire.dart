/// The vocabulary the client shares with the server: entity types, operations, field
/// names and the values of the enumerated fields.
///
/// **Each of these strings exists once, here.** The codec reads with them what the
/// repositories write with them; a typo in a second copy would not be a compile error
/// but a field that silently never arrives.
library;

/// The `entityType` of a change -- what the hand-written dispatcher decodes by.
/// Also the `itemType` of links, comments, shares and search hits.
abstract final class EntityTypes {
  static const todoList = 'TODO_LIST';
  static const todo = 'TODO';
  static const todoOccurrence = 'TODO_OCCURRENCE';
  static const calendar = 'CALENDAR';
  static const event = 'EVENT';
  static const calendarSubscription = 'CALENDAR_SUBSCRIPTION';
  static const calendarFeed = 'CALENDAR_FEED';
  static const wikiPage = 'WIKI_PAGE';
  static const comment = 'COMMENT';
  static const board = 'BOARD';
  static const widget = 'WIDGET';
  static const tag = 'TAG';

  /// A member's own order of the task lists — owned by them, shared with no one.
  static const listOrder = 'LIST_ORDER';

  /// An element on a pinboard, and a connection between two — items of their own in
  /// their page, so that each conflicts on its own.
  static const pinboardNode = 'PINBOARD_NODE';
  static const pinboardEdge = 'PINBOARD_EDGE';
}

/// The `op` of a mutation.
abstract final class SyncOps {
  static const upsert = 'upsert';
  static const delete = 'delete';
}

/// The names of the fields in a change's `fields`.
///
/// One list for all entity types: the same name means the same thing everywhere
/// (`title`, `tags`, `position`), and the version history labels them without
/// knowing the type.
abstract final class WireFields {
  // Shared by several types.
  static const name = 'name';
  static const title = 'title';
  static const description = 'description';
  static const kind = 'kind';
  static const colorToken = 'colorToken';
  static const position = 'position';
  static const tags = 'tags';
  static const archivedAt = 'archivedAt';
  static const archivedBy = 'archivedBy';
  static const token = 'token';

  // Lists and to-dos.
  static const assignees = 'assignees';
  static const columns = 'columns';
  static const listIds = 'listIds';
  static const listId = 'listId';
  static const status = 'status';
  static const dueDate = 'dueDate';
  static const dueTime = 'dueTime';
  static const rrule = 'rrule';
  static const amount = 'amount';
  static const unit = 'unit';
  static const productId = 'productId';
  static const columnId = 'columnId';
  static const occurrenceDate = 'occurrenceDate';
  static const doneAt = 'doneAt';
  static const doneBy = 'doneBy';
  static const skipped = 'skipped';

  // Calendars and events.
  static const calendarId = 'calendarId';
  static const calendarIds = 'calendarIds';
  static const location = 'location';
  static const note = 'note';
  static const timeForm = 'timeForm';
  static const allDay = 'allDay';
  static const startsAt = 'startsAt';
  static const endsAt = 'endsAt';
  static const startDate = 'startDate';
  static const endDate = 'endDate';
  static const localStart = 'localStart';
  static const localEnd = 'localEnd';
  static const timeZone = 'timeZone';
  static const exceptions = 'exceptions';
  static const attendees = 'attendees';
  static const reminderMinutes = 'reminderMinutes';
  static const defaultReminderMinutes = 'defaultReminderMinutes';
  static const url = 'url';
  static const targetKind = 'targetKind';
  static const targetListId = 'targetListId';
  static const syncInterval = 'syncInterval';
  static const lastSyncAt = 'lastSyncAt';
  static const lastError = 'lastError';
  static const importedCount = 'importedCount';
  static const contentMode = 'contentMode';

  // Wiki pages and comments.
  static const parentId = 'parentId';
  static const content = 'content';
  static const servings = 'servings';
  static const ingredients = 'ingredients';
  static const sourceUrl = 'sourceUrl';
  static const imageId = 'imageId';
  static const durationMinutes = 'durationMinutes';
  static const itemType = 'itemType';
  static const itemId = 'itemId';
  static const body = 'body';

  // A pinboard's elements and connections.
  static const x = 'x';
  static const y = 'y';
  static const width = 'width';
  static const height = 'height';
  static const layer = 'layer';
  static const text = 'text';
  static const target = 'target';
  static const linkView = 'linkView';
  static const color = 'color';
  static const shape = 'shape';
  static const textSize = 'textSize';
  static const textColor = 'textColor';
  static const points = 'points';
  static const strokeWidth = 'strokeWidth';
  static const line = 'line';
  static const rotation = 'rotation';
  static const textAlign = 'textAlign';
  static const textFlow = 'textFlow';

  /// A week of calendars: the calendars it shows, their ids separated by spaces, and
  /// its week as ISO 8601 writes it (`2027-W28`), none for the current one.
  static const calendars = 'calendars';
  static const week = 'week';
  static const arrows = 'arrows';
  static const fromId = 'fromId';
  static const toId = 'toId';

  // Boards and widgets.
  static const layout = 'layout';
  static const config = 'config';
  static const gridX = 'gridX';
  static const gridY = 'gridY';
  static const gridW = 'gridW';
  static const gridH = 'gridH';
}

/// The fields of one entry in an event's `exceptions`, keyed by the occurrence.
abstract final class EventExceptionFields {
  static const cancelled = 'cancelled';
  static const start = 'start';
  static const end = 'end';
}

/// What is stored is a **token, not a hex value**; the client maps
/// it to a color per theme.
abstract final class ColorTokens {
  static const blue = 'BLUE';
  static const rust = 'RUST';
  static const violet = 'VIOLET';
  static const green = 'GREEN';
  static const pink = 'PINK';
  static const ochre = 'OCHRE';
  static const teal = 'TEAL';
  static const slate = 'SLATE';

  // Tags only.
  static const red = 'RED';
  static const amber = 'AMBER';
}

/// The `kind` of a to-do list.
abstract final class ListKinds {
  static const standard = 'STANDARD';
  static const shopping = 'SHOPPING';
  static const kanban = 'KANBAN';
}

/// The `status` of a to-do.
abstract final class TodoStatuses {
  static const open = 'OPEN';
  static const done = 'DONE';
}

/// The `kind` of a calendar.
/// Special values of an event's `reminderMinutes`.
abstract final class ReminderMinutes {
  /// "No reminder" chosen on the event — it does not take its calendar's default.
  /// `null` instead means "none of its own", and the default applies.
  static const none = -1;
}

abstract final class CalendarKinds {
  static const local = 'LOCAL';
  static const external = 'EXTERNAL';
}

/// The `timeForm` of an event.
abstract final class TimeForms {
  static const timed = 'TIMED';
  static const allDay = 'ALL_DAY';
  static const recurring = 'RECURRING';
}

/// The `targetKind` of a calendar subscription: what the entries become.
abstract final class SubscriptionTargets {
  static const event = 'EVENT';
  static const task = 'TASK';
}

/// The `syncInterval` of a calendar subscription.
abstract final class SyncIntervals {
  static const hourly = 'HOURLY';
  static const daily = 'DAILY';
  static const weekly = 'WEEKLY';
}

/// The `contentMode` of a calendar feed.
abstract final class FeedContentModes {
  static const full = 'FULL';
  static const busy = 'BUSY';
}

/// The `kind` of a wiki page.
abstract final class PageKinds {
  static const page = 'PAGE';
  static const recipe = 'RECIPE';
  static const pinboard = 'PINBOARD';
}

/// The `kind` of an element on a pinboard. The list may grow: an element of a kind
/// this app does not know is drawn as a placeholder and kept as it is.
abstract final class PinboardKinds {
  /// Text without formatting — a snippet written anywhere on the canvas.
  static const plain = 'PLAIN';

  /// Markdown, written in the same editor as a page.
  static const note = 'NOTE';
  static const image = 'IMAGE';
  static const link = 'LINK';

  /// A member of the family, shown by their picture — its `target` names them
  /// (`hiwiski://member/<id>`).
  static const member = 'MEMBER';

  /// A stroke drawn by hand — its `points` across the element.
  static const drawing = 'DRAWING';

  /// A week of calendars, side by side — its `calendars` and its `week`.
  static const calendar = 'CALENDAR';
}

/// What a link element shows of its target. An unknown one shows the title.
abstract final class PinboardLinkViews {
  /// The target's symbol and title.
  static const title = 'TITLE';

  /// The target as its preview shows it.
  static const content = 'CONTENT';
}

/// The outline of an element. An unknown one is drawn rounded.
abstract final class PinboardShapes {
  static const rectangle = 'RECTANGLE';
  static const rounded = 'ROUNDED';
  static const ellipse = 'ELLIPSE';
  static const pill = 'PILL';
  static const diamond = 'DIAMOND';

  /// What a stroke may have been drawn as, besides [rectangle], [ellipse] and
  /// [diamond].
  static const triangle = 'TRIANGLE';
  static const line = 'LINE';
  static const arrow = 'ARROW';
}

/// The line a connection is drawn with. An unknown one is drawn solid.
abstract final class PinboardLines {
  static const solid = 'SOLID';
  static const dashed = 'DASHED';
  static const dotted = 'DOTTED';
}

/// Where a connection has arrow heads: at the element it goes to, the one it comes
/// from, both or neither. An unknown one is drawn without.
abstract final class PinboardArrows {
  static const none = 'NONE';
  static const end = 'END';
  static const start = 'START';
  static const both = 'BOTH';
}

/// Where a note's text stands inside it. An unknown one is top left.
abstract final class PinboardTextAligns {
  static const topLeft = 'TOP_LEFT';
  static const topCenter = 'TOP_CENTER';
  static const topRight = 'TOP_RIGHT';
  static const middleLeft = 'MIDDLE_LEFT';
  static const center = 'CENTER';
  static const middleRight = 'MIDDLE_RIGHT';
  static const bottomLeft = 'BOTTOM_LEFT';
  static const bottomCenter = 'BOTTOM_CENTER';
  static const bottomRight = 'BOTTOM_RIGHT';

  /// Row by row, from the top left.
  static const all = [
    topLeft,
    topCenter,
    topRight,
    middleLeft,
    center,
    middleRight,
    bottomLeft,
    bottomCenter,
    bottomRight,
  ];
}

/// What a note's lines fill. An unknown one is [box].
abstract final class PinboardTextFlows {
  /// The largest box inside the note's shape: every line as wide as it.
  static const box = 'BOX';

  /// The shape itself: each line as wide as the shape is at its height.
  static const shape = 'SHAPE';
}

/// The size of an element's text.
abstract final class PinboardTextSizes {
  static const small = 'S';
  static const medium = 'M';
  static const large = 'L';
  static const xLarge = 'XL';
}

/// The `kind` of a board.
abstract final class BoardKinds {
  static const start = 'START';
  static const dashboard = 'DASHBOARD';
}

/// The `layout` of a board.
abstract final class BoardLayouts {
  static const flow = 'FLOW';
  static const grid = 'GRID';
}

/// The zone when none is known: off for everyone, but never missing.
const utcTimeZone = 'UTC';
