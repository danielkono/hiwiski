/// The parts of an RFC 5545 recurrence rule the app reads and writes.
abstract final class RruleParts {
  /// The rule as a content line. The server stores it **without** this prefix.
  static const prefix = 'RRULE:';

  static const freq = 'FREQ';
  static const interval = 'INTERVAL';
  static const byDay = 'BYDAY';
  static const count = 'COUNT';
  static const until = 'UNTIL';
  static const weekStart = 'WKST';

  /// Parts the app never writes, read only to refuse what the devices cannot expand
  /// (`golden/recurrence-limits.json`).
  static const bySetPosition = 'BYSETPOS';
  static const byWeekNumber = 'BYWEEKNO';
  static const byYearDay = 'BYYEARDAY';
  static const byHour = 'BYHOUR';
  static const byMinute = 'BYMINUTE';
  static const hourly = 'HOURLY';
  static const minutely = 'MINUTELY';
  static const secondly = 'SECONDLY';

  static const daily = 'DAILY';
  static const weekly = 'WEEKLY';
  static const monthly = 'MONTHLY';
  static const yearly = 'YEARLY';

  /// Between the date and the time of a date-time, and the mark of UTC after it.
  static const timeSeparator = 'T';
  static const utc = 'Z';

  /// The time of an `UNTIL` that includes its whole day.
  static const endOfDay = '${timeSeparator}235959$utc';
}
