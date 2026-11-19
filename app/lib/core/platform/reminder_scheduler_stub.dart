import 'reminder_scheduler.dart';

/// For platforms that have neither `dart:io` nor `dart:js_interop` — there are none.
/// The branch exists because a conditional import needs a default case.
ReminderScheduler createPlatformScheduler() => const _NoScheduler();

class _NoScheduler implements ReminderScheduler {
  const _NoScheduler();

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
