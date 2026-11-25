/// The `DateFormat` patterns of the app, in one place.
///
/// The short forms follow the design (`Mo, 05.10.`) and stay the same in every
/// language; what changes with the language are the names of days and months, which
/// `DateFormat` takes from the locale.
abstract final class DatePatterns {
  static const dayMonth = 'dd.MM.';
  static const dayMonthYear = 'dd.MM.yyyy';
  static const weekdayDayMonth = 'E, dd.MM.';
  static const dayMonthName = 'd. MMM';

  /// The wire form of a date without a time.
  static const isoDate = 'yyyy-MM-dd';

  static const time24 = 'HH:mm';
  static const time24Seconds = 'HH:mm:ss';
  static const time12 = 'h:mm a';
  static const time12Seconds = 'h:mm:ss a';
}
