import 'reminder_scheduler.dart';

/// The browser has no reminders.
///
/// A notification would only be possible while the tab is open — and a reminder that only
/// arrives when you are looking anyway is no reminder. So the app says so instead of
/// pretending.
ReminderScheduler createPlatformScheduler() => const WebScheduler();

class WebScheduler implements ReminderScheduler {
  const WebScheduler();

  @override
  bool get supported => false;

  @override
  Future<void> initialize(String timeZone, {bool askPermission = true}) async {}

  @override
  Future<void> replaceAll(List<PendingReminder> reminders) async {}

  @override
  Stream<String> get opened => const .empty();

  @override
  Future<String?> takeLaunchPayload() async => null;
}
