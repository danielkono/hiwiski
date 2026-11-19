// The domain models of this feature, field for field what the local database
// stores. The repository maps its rows onto them: the layers above see these
// classes, never a Drift row.

/// A calendar: local, or fed by a subscription.
class Calendar {
  const Calendar({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.name,
    required this.colorToken,
    required this.kind,
    required this.position,
    required this.tags,
    this.defaultReminderMinutes,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String name;
  final String colorToken;
  final String kind;
  final int position;
  final String tags;

  /// Minutes before the start for every event without a reminder of its own.
  final int? defaultReminderMinutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Calendar &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.name == name &&
          other.colorToken == colorToken &&
          other.kind == kind &&
          other.position == position &&
          other.tags == tags &&
          other.defaultReminderMinutes == defaultReminderMinutes;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    name,
    colorToken,
    kind,
    position,
    tags,
    defaultReminderMinutes,
  ]);
}

/// An event — once, all day, or a series with its exceptions.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.calendarId,
    this.entityKey,
    required this.title,
    this.description,
    this.location,
    required this.timeForm,
    this.startsAt,
    this.endsAt,
    this.startDate,
    this.endDate,
    this.localStart,
    this.localEnd,
    this.timeZone,
    this.rrule,
    required this.exceptions,
    required this.attendees,
    required this.tags,
    this.reminderMinutes,
    this.sourceUid,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String calendarId;
  final String? entityKey;
  final String title;
  final String? description;
  final String? location;
  final String timeForm;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? localStart;
  final String? localEnd;
  final String? timeZone;
  final String? rrule;
  final String exceptions;
  final String attendees;
  final String tags;
  final int? reminderMinutes;
  final String? sourceUid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarEvent &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.calendarId == calendarId &&
          other.entityKey == entityKey &&
          other.title == title &&
          other.description == description &&
          other.location == location &&
          other.timeForm == timeForm &&
          other.startsAt == startsAt &&
          other.endsAt == endsAt &&
          other.startDate == startDate &&
          other.endDate == endDate &&
          other.localStart == localStart &&
          other.localEnd == localEnd &&
          other.timeZone == timeZone &&
          other.rrule == rrule &&
          other.exceptions == exceptions &&
          other.attendees == attendees &&
          other.tags == tags &&
          other.reminderMinutes == reminderMinutes &&
          other.sourceUid == sourceUid;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    calendarId,
    entityKey,
    title,
    description,
    location,
    timeForm,
    startsAt,
    endsAt,
    startDate,
    endDate,
    localStart,
    localEnd,
    timeZone,
    rrule,
    exceptions,
    attendees,
    tags,
    reminderMinutes,
    sourceUid,
  ]);
}

/// An ICS address the server fetches into a calendar.
class CalendarSubscription {
  const CalendarSubscription({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.calendarId,
    required this.name,
    required this.url,
    required this.targetKind,
    this.targetListId,
    required this.syncInterval,
    this.lastSyncAt,
    this.lastError,
    required this.importedCount,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String calendarId;
  final String name;
  final String url;
  final String targetKind;
  final String? targetListId;
  final String syncInterval;
  final DateTime? lastSyncAt;
  final String? lastError;
  final int importedCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarSubscription &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.calendarId == calendarId &&
          other.name == name &&
          other.url == url &&
          other.targetKind == targetKind &&
          other.targetListId == targetListId &&
          other.syncInterval == syncInterval &&
          other.lastSyncAt == lastSyncAt &&
          other.lastError == lastError &&
          other.importedCount == importedCount;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    calendarId,
    name,
    url,
    targetKind,
    targetListId,
    syncInterval,
    lastSyncAt,
    lastError,
    importedCount,
  ]);
}

/// An ICS export of some calendars, reachable by its token.
class CalendarFeed {
  const CalendarFeed({
    required this.id,
    required this.ownerId,
    required this.version,
    this.deletedAt,
    required this.name,
    required this.calendarIds,
    required this.contentMode,
    required this.token,
  });

  final String id;
  final String ownerId;
  final int version;
  final DateTime? deletedAt;
  final String name;
  final String calendarIds;
  final String contentMode;
  final String token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarFeed &&
          other.id == id &&
          other.ownerId == ownerId &&
          other.version == version &&
          other.deletedAt == deletedAt &&
          other.name == name &&
          other.calendarIds == calendarIds &&
          other.contentMode == contentMode &&
          other.token == token;

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    version,
    deletedAt,
    name,
    calendarIds,
    contentMode,
    token,
  ]);
}
