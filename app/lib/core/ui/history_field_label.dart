import '../common/wire.dart';
import '../l10n/generated/app_localizations.dart';

/// The field name as humans call it.
///
/// The words are the ones the form uses too — "Due" is the same word on a task and in
/// the history, and two translations of the same field would be two truths. **An
/// unknown field stays visible**, just like an unknown error code: ugly and honest.
/// An older app must not swallow a new field from the
/// server.
String historyFieldLabel(L l, String field) => switch (field) {
  WireFields.title => l.wikiPageTitle,
  WireFields.description ||
  WireFields.content ||
  WireFields.note ||
  WireFields.body ||
  WireFields.text => l.historyFieldText,
  // A pinboard's elements and connections.
  WireFields.x || WireFields.y => l.pinboardFieldPosition,
  WireFields.width || WireFields.height => l.pinboardFieldSize,
  WireFields.layer => l.pinboardFieldLayer,
  WireFields.target => l.pinboardFieldTarget,
  WireFields.color => l.calColor,
  WireFields.shape => l.pinboardShape,
  WireFields.textSize => l.pinboardTextSize,
  WireFields.textColor => l.pinboardTextColor,
  WireFields.points => l.pinboardKindDrawing,
  WireFields.strokeWidth => l.pinboardStrokeWidth,
  WireFields.linkView => l.pinboardLinkView,
  WireFields.fromId || WireFields.toId => l.pinboardFieldEnds,
  WireFields.rotation => l.pinboardFieldRotation,
  WireFields.textAlign => l.pinboardTextAlign,
  WireFields.textFlow => l.pinboardTextFlow,
  WireFields.calendars => l.pinboardFieldCalendars,
  WireFields.week => l.pinboardFieldWeek,
  // One choice in the form: a dashed arrow is a kind of line.
  WireFields.line || WireFields.arrows => l.pinboardEdgeStyle,
  WireFields.tags => l.tagsTitle,
  WireFields.kind => l.historyFieldKind,
  WireFields.archivedAt || WireFields.archivedBy => l.archiveTitle,
  WireFields.status => l.historyFieldStatus,
  WireFields.dueDate || WireFields.dueTime => l.todoDue,
  WireFields.rrule => l.todoRepeat,
  WireFields.assignees || WireFields.attendees => l.calAssigned,
  WireFields.location => l.calLocation,
  WireFields.startsAt ||
  WireFields.startDate ||
  WireFields.localStart => l.calStart,
  WireFields.endsAt || WireFields.endDate || WireFields.localEnd => l.calEnd,
  WireFields.timeForm || WireFields.allDay => l.calAllDay,
  WireFields.timeZone => l.historyFieldTimeZone,
  WireFields.exceptions => l.historyFieldOccurrences,
  WireFields.reminderMinutes ||
  WireFields.defaultReminderMinutes => l.calReminder,
  WireFields.calendarId ||
  WireFields.listId ||
  WireFields.parentId ||
  WireFields.position => l.historyFieldOrder,
  WireFields.colorToken => l.calColor,
  WireFields.columns => l.kanbanColumns,
  WireFields.columnId => l.kanbanColumn,
  WireFields.name => l.wikiPageTitle,
  WireFields.servings => l.recipeServings,
  WireFields.ingredients => l.recipeIngredients,
  WireFields.imageId => l.historyFieldImage,
  WireFields.sourceUrl => l.recipeSource,
  WireFields.durationMinutes => l.recipeDuration,
  WireFields.amount ||
  WireFields.unit ||
  WireFields.productId => l.historyFieldAmount,
  _ => field,
};
