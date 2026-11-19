import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../common/app_names.dart';
import 'reminder_scheduler.dart';

ReminderScheduler createPlatformScheduler() => LocalNotificationScheduler();

/// Reminders via `flutter_local_notifications`.
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'hiwiski.reminders';
  static const _icon = '@mipmap/ic_launcher';

  tz.Location? _location;
  bool _ready = false;
  bool _launchTaken = false;

  final _opened = StreamController<String>.broadcast();

  @override
  Stream<String> get opened => _opened.stream;

  /// Desktop Linux has no scheduler in the library.
  @override
  bool get supported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  Future<void> initialize(String timeZone, {bool askPermission = true}) async {
    if (!supported || _ready) return;
    _location = _resolve(timeZone);
    // Darwin asks during `initialize` unless told otherwise.
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: askPermission,
      requestBadgePermission: askPermission,
      requestSoundPermission: askPermission,
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings(_icon),
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload case final payload? when payload.isNotEmpty) {
          _opened.add(payload);
        }
      },
    );
    // Android 13+ shows nothing without the runtime permission; earlier versions grant
    // it at install and the call returns at once.
    if (askPermission) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    _ready = true;
  }

  @override
  Future<void> replaceAll(List<PendingReminder> reminders) async {
    if (!supported) return;
    if (!_ready) return;

    // Only what is still to come: `cancelAll` also takes away the reminders already
    // shown, and this runs after every sync.
    await _plugin.cancelAllPendingNotifications();
    final location = _location ?? tz.UTC;

    for (final reminder in reminders) {
      // One that passed while the others were being scheduled is skipped here: the
      // platform refuses a date in the past.
      if (!reminder.when.isAfter(clock.now())) continue;
      try {
        await _schedule(reminder, location);
      } on Object catch (error) {
        // One refused reminder must not cost the rest. It used to end the loop, after
        // the old ones had already been cancelled: no reminders until the next run.
        if (kDebugMode) {
          debugPrint('hiwiski: reminder ${reminder.id} not scheduled: $error');
        }
      }
    }
  }

  @override
  Future<String?> takeLaunchPayload() async {
    if (!_ready || _launchTaken) return null;
    _launchTaken = true;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (!(details?.didNotificationLaunchApp ?? false)) return null;
    return details?.notificationResponse?.payload;
  }

  Future<void> _schedule(
    PendingReminder reminder,
    tz.Location location,
  ) => _plugin.zonedSchedule(
    id: reminder.id,
    title: reminder.title,
    body: reminder.body,
    payload: reminder.payload,
    scheduledDate: tz.TZDateTime.from(reminder.when, location),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        // The channel name shows up in the system settings and is therefore UI —
        // it would come from the ARB files if the library did not fix it once
        // when the channel is created.
        AppNames.product,
        importance: .defaultImportance,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    ),
    // `inexact`, because `exact` needs a permission of its own since Android 13 —
    // and a reminder that wobbles by a minute is better than one that fails on a
    // permission prompt.
    androidScheduleMode: .inexactAllowWhileIdle,
    // No `matchDateTimeComponents`: every occurrence of a series is scheduled
    // separately. A repeating notification does not know the series' exceptions
    // and would remind of cancelled events.
  );

  static tz.Location _resolve(String timeZone) {
    try {
      return tz.getLocation(timeZone);
    } on Object catch (_) {
      return tz.UTC;
    }
  }
}
