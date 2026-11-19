/// Where an import goes: one of our calendars, or a new one the import creates.
sealed class ImportTarget {
  const ImportTarget();
}

final class ExistingCalendar extends ImportTarget {
  const ExistingCalendar(this.calendarId);

  final String calendarId;
}

final class NewCalendar extends ImportTarget {
  const NewCalendar({
    required this.name,
    required this.colorToken,
    required this.locked,
  });

  final String name;
  final String colorToken;

  /// Read only, like a subscription — only a further import changes it.
  final bool locked;
}
