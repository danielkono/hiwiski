import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/routes.dart';
import '../data/calendar/reminder_repository.dart';
import 'repositories.dart';
import 'router.dart';

/// A tapped reminder opens its event, at the occurrence it was for. Before, a tap
/// opened the app where it had been left.
///
/// The taps while the app runs; they come once [ReminderRepository.initialize] has
/// set up the scheduler.
StreamSubscription<ReminderTarget> listenForReminderTaps(WidgetRef ref) => ref
    .read(reminderRepositoryProvider)
    .opened
    .listen((target) => _open(ref, target));

/// The reminder the app was started with: its event, once — after
/// [ReminderRepository.initialize].
Future<void> openLaunchReminder(WidgetRef ref) async {
  final target = await ref.read(reminderRepositoryProvider).takeLaunchTarget();
  if (target != null) _open(ref, target);
}

void _open(WidgetRef ref, ReminderTarget target) => ref
    .read(routerProvider)
    .go(
      EventRoute(
        eventId: target.eventId,
        at: target.start.toIso8601String(),
      ).location,
    );
