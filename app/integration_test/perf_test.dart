import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/router.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/core/routing/routes.dart';
import 'package:hiwiski/features/calendar/overview/calendar_overview_view_model.dart';
import 'package:hiwiski/features/search/view/search_keys.dart';
import 'package:hiwiski/main.dart' as app;
import 'package:uuid/uuid.dart';

/// A performance run through every area against a filled instance.
///
/// Measures, per step, how long until the screen stands still (no more frames
/// scheduled) and the frame timings while it works. On a physical device — profile
/// mode is off on emulators:
///
/// ```sh
/// adb reverse tcp:8090 tcp:8090
/// PERF_OUT=<name> flutter drive --profile -d <device> \
///   --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart \
///   --dart-define=SERVER=http://localhost:8090 --dart-define=USER=… \
///   --dart-define=PASSWORD=… --dart-define=OTHER_PASSWORD=… \
///   --dart-define=LIST=<id> …  # and the other ids read below
/// ```
///
/// The report lands in `build/perf/<name>.json`. For CPU profiles of the steps in
/// [_profiled], start `integration_test/perf_sampler.dart` with the VM service address `flutter
/// drive` prints.
const _server = String.fromEnvironment('SERVER');
const _user = String.fromEnvironment('USER');
const _password = String.fromEnvironment('PASSWORD');
const _list = String.fromEnvironment('LIST');
const _shop = String.fromEnvironment('SHOP');
const _kanban = String.fromEnvironment('KANBAN');
const _page = String.fromEnvironment('PAGE');
const _recipe = String.fromEnvironment('RECIPE');
const _todoList = String.fromEnvironment('TODO_LIST');
const _todo = String.fromEnvironment('TODO');
const _event = String.fromEnvironment('EVENT');

/// Someone else who writes while the device watches: a parent with write access.
const _otherUser = String.fromEnvironment('OTHER_USER', defaultValue: 'markus');
const _otherPassword = String.fromEnvironment('OTHER_PASSWORD');

/// The steps whose CPU samples a host-side sampler breaks down — the expensive ones of
/// the first run.
const _profiled = {
  'login_and_snapshot',
  'trash',
  'calendar_open',
  'calendar_week',
  'calendar_month',
  'event_detail',
  'list_big',
  'list_shopping',
  'remote_burst_300_new',
  'wiki_open',
  'wiki_big_page',
  'tab_round_trip',
};

Future<Map<String, dynamic>> _api(
  String method,
  String path, {
  String? token,
  Object? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse('$_server$path'));
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final report = <String, Object?>{};

  testWidgets('performance run', (tester) async {
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => timings.addAll(frames);

    /// Real time until nothing is scheduled any more — or [limit].
    Future<int> settle({Duration limit = const Duration(seconds: 60)}) async {
      final watch = Stopwatch()..start();
      int quiet = 0;
      while (watch.elapsed < limit) {
        await tester.pump(const Duration(milliseconds: 16));
        // A spinning progress indicator means loading: busy. One with a value is a
        // progress bar (a list's share of done tasks) and stands still.
        bool spinning(Finder finder) => finder.evaluate().any(
          (e) => (e.widget as ProgressIndicator).value == null,
        );
        final busy =
            SchedulerBinding.instance.hasScheduledFrame ||
            spinning(find.byType(LinearProgressIndicator)) ||
            spinning(find.byType(CircularProgressIndicator));
        quiet = busy ? 0 : quiet + 1;
        if (quiet >= 6) break;
      }
      return watch.elapsedMilliseconds;
    }

    Map<String, Object?> frameStats(List<FrameTiming> frames) {
      if (frames.isEmpty) return {'frames': 0};
      List<double> sorted(Iterable<Duration> values) =>
          [for (final d in values) d.inMicroseconds / 1000]..sort();
      double p(List<double> values, double q) =>
          values[((values.length - 1) * q).round()];
      final build = sorted(frames.map((f) => f.buildDuration));
      final raster = sorted(frames.map((f) => f.rasterDuration));
      final total = sorted(frames.map((f) => f.totalSpan));
      return {
        'frames': frames.length,
        'build_p50': p(build, .5),
        'build_p90': p(build, .9),
        'build_max': build.last,
        'raster_p90': p(raster, .9),
        'raster_max': raster.last,
        // Over 16.7 ms: a frame that missed 60 Hz.
        'janky': total.where((t) => t > 16.7).length,
        'worst_ms': total.last,
      };
    }

    /// Runs [action], then waits for the screen to stand still.
    Future<void> step(String name, AsyncCallback action) async {
      timings.clear();
      SchedulerBinding.instance.addTimingsCallback(collect);
      final cpuStart = developer.Timeline.now;
      final watch = Stopwatch()..start();
      await action();
      final settled = await settle();
      watch.stop();
      final cpuEnd = developer.Timeline.now;
      if (_profiled.contains(name)) {
        // A sampler on the host (integration_test/perf_sampler.dart) fetches this window's CPU
        // samples through the VM service; give it a moment while they are fresh.
        developer.postEvent('hiwiski.perf', {
          'name': name,
          'start': cpuStart,
          'end': cpuEnd,
        });
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      // Timings arrive in batches; give the last ones a moment.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      SchedulerBinding.instance.removeTimingsCallback(collect);
      report[name] = {
        'ms': watch.elapsedMilliseconds,
        'settle_ms': settled,
        ...frameStats(timings),
      };
      // ignore: avoid_print
      print('PERF $name ${report[name]}');
    }

    ProviderContainer container() =>
        ProviderScope.containerOf(tester.element(find.byType(app.HiwiskiApp)));
    GoRouter router() => container().read(routerProvider);
    Future<void> go(String location) async => router().go(location);

    /// The biggest visible list that scrolls along [axis] — not one lying under the
    /// current page in the navigation stack.
    Finder scrollable(Axis axis) {
      final candidates = find
          .byType(Scrollable)
          .hitTestable()
          .evaluate()
          .where(
            (element) =>
                axisDirectionToAxis(
                  (element.widget as Scrollable).axisDirection,
                ) ==
                axis,
          );
      Element? best;
      double area = 0.0;
      for (final element in candidates) {
        final size = (element.renderObject as RenderBox?)?.size ?? .zero;
        if (size.width * size.height > area) {
          area = size.width * size.height;
          best = element;
        }
      }
      return best == null
          ? find.byType(Scrollable).hitTestable().first
          : find.byElementPredicate((e) => e == best);
    }

    Future<void> fling(Offset offset, {int times = 4, Finder? on}) async {
      final axis = offset.dx.abs() > offset.dy.abs()
          ? Axis.horizontal
          : Axis.vertical;
      for (int i = 0; i < times; i++) {
        await tester.fling(on ?? scrollable(axis), offset, 3000);
        await settle(limit: const Duration(seconds: 5));
      }
    }

    // ---------------------------------------------------------------- start up
    final launch = Stopwatch()..start();
    unawaited(app.main());
    while (find.byType(TextField).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    report['launch_to_first_screen_ms'] = launch.elapsedMilliseconds;

    // Server address, then sign in. On a device the test text input does not reach
    // the fields: the text goes straight into their controllers, then a tap.
    void type(Finder field, String text) =>
        tester.widget<TextField>(field).controller!.text = text;
    // A button is pressed through its callback: on a phone the real keyboard comes up
    // and covers what lies below the field, and a tap there misses.
    Future<void> press(Finder button) async {
      FocusManager.instance.primaryFocus?.unfocus();
      tester.widget<ButtonStyleButton>(button).onPressed!();
      await tester.pump(const Duration(milliseconds: 100));
    }

    type(find.byType(TextField).first, _server);
    await press(find.byType(FilledButton).first);
    // Over plain http the app asks to confirm ("Continue") — the second button.
    while (find.byType(TextField).evaluate().length < 2) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(FilledButton).evaluate().length > 1) {
        await press(find.byType(FilledButton).last);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    type(find.byType(TextField).at(0), _user);
    type(find.byType(TextField).at(1), _password);

    await step('login_and_snapshot', () async {
      await press(find.byType(FilledButton).first);
      // Until the first pull is through.
      final limit = Stopwatch()..start();
      while (limit.elapsed < const Duration(minutes: 5)) {
        await tester.pump(const Duration(milliseconds: 100));
        final status = container().read(syncStatusProvider);
        if (status.lastSyncedAt != null && !status.syncing) break;
      }
    });

    // ---------------------------------------------------------------- areas
    await step('start', () => go(const HomeRoute().location));
    await step('start_scroll', () => fling(const Offset(0, -600)));

    await step('calendar_open', () => go(const CalendarRoute().location));
    final view = container().read(calendarOverviewViewModelProvider.notifier);
    await step('calendar_list', () => view.setMode(CalendarViewMode.list));
    await step(
      'calendar_list_scroll',
      () => fling(const Offset(0, -900), times: 6),
    );
    await step('calendar_week', () => view.setMode(CalendarViewMode.week));
    await step(
      'calendar_week_swipe',
      () => fling(const Offset(-500, 0), times: 4),
    );
    await step('calendar_month', () => view.setMode(CalendarViewMode.month));
    await step(
      'calendar_month_swipe',
      () => fling(const Offset(-500, 0), times: 4),
    );
    await step(
      'event_detail',
      () => go(const EventRoute(eventId: _event).location),
    );
    await step('event_detail_scroll', () => fling(const Offset(0, -900)));

    await step('tasks_open', () => go(const TodoRoute().location));
    await step('tasks_scroll', () => fling(const Offset(0, -900)));
    await step(
      'list_big',
      () => go(const TodoListRoute(listId: _list).location),
    );
    await step('list_big_scroll', () => fling(const Offset(0, -900), times: 6));
    // While the big list is open, someone else adds 300 tasks to it — and deletes them.
    if (_otherPassword.isNotEmpty) {
      final other = await _api(
        'POST',
        '/api/v1/auth/login',
        body: {
          'username': _otherUser,
          'password': _otherPassword,
          'device': {
            'deviceName': 'perf burst',
            'platform': 'LINUX',
            'staySignedIn': false,
          },
        },
      );
      final token = other['token'] as String;
      final device = (other['session'] as Map)['deviceId'];
      final ids = [for (int i = 0; i < 300; i++) const Uuid().v7()];
      final versions = <String, int>{};

      Future<void> burst(List<Map<String, Object?>> mutations) async {
        final answer = await _api(
          'POST',
          '/api/v1/sync/push',
          token: token,
          body: {'deviceId': device, 'mutations': mutations},
        );
        for (final result in (answer['results'] as List).cast<Map>()) {
          if (result['version'] != null) {
            versions[result['entityId'] as String] = result['version'] as int;
          }
        }
        final pushed = DateTime.now();
        await container().read(syncRepositoryProvider).syncNow();
        final limit = Stopwatch()..start();
        while (limit.elapsed < const Duration(minutes: 3)) {
          await tester.pump(const Duration(milliseconds: 50));
          final status = container().read(syncStatusProvider);
          if (!status.syncing &&
              (status.lastSyncedAt?.isAfter(pushed) ?? false)) {
            break;
          }
        }
      }

      await step(
        'remote_burst_300_new',
        () => burst([
          for (final (i, id) in ids.indexed)
            {
              'mutationId': const Uuid().v7(),
              'entityType': 'TODO',
              'entityId': id,
              'op': 'upsert',
              'containerType': 'TODO_LIST',
              'containerId': _list,
              'fields': {
                'listId': _list,
                'title': 'Burst $i',
                'status': 'OPEN',
                'position': 1000 + i,
              },
            },
        ]),
      );
      await step(
        'remote_burst_300_deleted',
        () => burst([
          for (final id in ids)
            {
              'mutationId': const Uuid().v7(),
              'entityType': 'TODO',
              'entityId': id,
              'op': 'delete',
              'baseVersion': versions[id],
              'containerType': 'TODO_LIST',
              'containerId': _list,
            },
        ]),
      );
      await _api('POST', '/api/v1/auth/logout', token: token);
    }

    await step(
      'list_shopping',
      () => go(const TodoListRoute(listId: _shop).location),
    );
    await step('list_shopping_scroll', () => fling(const Offset(0, -900)));
    await step(
      'kanban',
      () => go(const TodoListRoute(listId: _kanban).location),
    );
    await step('kanban_swipe', () => fling(const Offset(-600, 0), times: 3));
    await step(
      'todo_detail',
      () =>
          go(const TodoDetailRoute(listId: _todoList, todoId: _todo).location),
    );
    await step('todo_detail_scroll', () => fling(const Offset(0, -900)));

    await step('wiki_open', () => go(const WikiRoute().location));
    await step(
      'wiki_tree_scroll',
      () => fling(const Offset(0, -900), times: 6),
    );
    await step(
      'wiki_big_page',
      () => go(const WikiRoute(pageId: _page).location),
    );
    await step(
      'wiki_big_page_scroll',
      () => fling(const Offset(0, -1200), times: 10),
    );
    await step(
      'wiki_recipe',
      () => go(const WikiRoute(pageId: _recipe).location),
    );

    await step('search_open', () => go(const SearchRoute().location));
    await step('search_query', () async {
      final input = find.byKey(SearchKeys.searchInput);
      type(input, 'Termin');
      tester.widget<TextField>(input).onChanged!('Termin');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await step('search_scroll', () => fling(const Offset(0, -900)));

    await step('archive', () => go(const ArchiveRoute().location));
    await step('trash', () => go(const TrashRoute().location));

    // Switching areas back and forth, three rounds.
    await step('tab_round_trip', () async {
      for (int round = 0; round < 3; round++) {
        for (final location in [
          const HomeRoute().location,
          const CalendarRoute().location,
          const TodoRoute().location,
          const WikiRoute().location,
        ]) {
          await go(location);
          await settle(limit: const Duration(seconds: 10));
        }
      }
    });

    binding.reportData = report;
  }, timeout: const Timeout(Duration(minutes: 20)));
}
