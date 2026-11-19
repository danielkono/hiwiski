import 'reminder_scheduler_stub.dart'
    if (dart.library.io) 'reminder_scheduler_io.dart'
    if (dart.library.js_interop) 'reminder_scheduler_web.dart';

/// A scheduled reminder.
class const PendingReminder({
  /// A stable 31-bit identifier. The platforms want `int`, not a UUID.
  required final int id,
  required final String title,
  required final String body,

  /// Local time.
  required final DateTime when,

  /// What a tap on it opens — handed back through [ReminderScheduler.opened].
  required final String payload,
});

/// What a platform has to be able to do so that reminders arrive.
///
/// **Local, without a service and without network**: no FCM, no APNs, no
/// Google account. The price is that a reminder only exists on the device the app is
/// on — and for a self-hosted family app that is the right price.
abstract class ReminderScheduler {
  /// Whether this platform can schedule reminders at all.
  ///
  /// Not in the browser. That is **said**, not hidden: "The browser has no reminders.
  /// Phones and tablets do." A switch that does nothing is worse than a missing
  /// switch.
  bool get supported;

  /// Once at startup. `timeZone` is the device's IANA name — a reminder is scheduled
  /// in local time, not in UTC.
  ///
  /// [askPermission] is `false` for a run without the app on screen: a permission
  /// prompt needs somebody to answer it, and whoever has not been asked yet is asked
  /// when the app is opened.
  Future<void> initialize(String timeZone, {bool askPermission = true});

  /// Replaces **all** scheduled reminders. One that was already shown stays where the
  /// system shows it: this runs after every sync, also without the app, and a reminder
  /// must not vanish minutes after it rang.
  ///
  /// Never catch up one by one: an event can move through sync, through a series or
  /// through an exception, and bookkeeping over which identifier currently belongs to
  /// which occurrence would be the kind of state that drifts apart.
  Future<void> replaceAll(List<PendingReminder> reminders);

  /// The [PendingReminder.payload] of every reminder tapped while the app runs.
  Stream<String> get opened;

  /// The payload of the reminder the app was started with — once; `null` after that,
  /// and when it was started otherwise. After [initialize].
  Future<String?> takeLaunchPayload();
}

/// This platform's implementation.
ReminderScheduler createReminderScheduler() => createPlatformScheduler();
