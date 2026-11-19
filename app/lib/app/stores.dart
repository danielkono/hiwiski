import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/calendar/calendar_day_store.dart';
import '../data/home_widgets/home_widget_store.dart';
import '../data/navigation/area_memory_store.dart';
import '../data/preferences/preferences_store.dart';
import '../data/session/session_store.dart';
import '../data/tags/tag_filter_store.dart';
import '../data/todo/todo_sidebar_store.dart';
import '../data/update/web_update_store.dart';
import '../data/wiki/wiki_tree_store.dart';
import '../domain/home_widgets/home_widget_settings.dart';
import '../domain/preferences/preferences.dart';
import '../domain/session/session_state.dart';
import '../core/sync/sync_status.dart';
import 'data_providers.dart';
import 'demo.dart';
import 'repositories.dart';

part 'stores.g.dart';

// The stores — state several screens share (points 2 and 3).
// Each comes twice: the store itself, for the commands, and its value, for watching.
// The value follows the store synchronously: a screen that has just changed it reads
// the new value at once.

/// [store]'s value, kept in [set] the moment the store announces a change.
T _follow<T>(Ref ref, ValueListenable<T> store, void Function(T value) set) {
  void changed() => set(store.value);
  store.addListener(changed);
  ref.onDispose(() => store.removeListener(changed));
  return store.value;
}

/// A store that lives as long as its provider.
S _owned<S extends ChangeNotifier>(Ref ref, S store) {
  ref.onDispose(store.dispose);
  return store;
}

// --- Preferences ----------------------------------------------------------------

@Riverpod(keepAlive: true)
PreferencesStore preferencesStore(Ref ref) =>
    _owned(ref, PreferencesStore(ref.watch(localSettingsProvider)));

@Riverpod(keepAlive: true, name: 'preferencesProvider')
class PreferencesValue extends _$PreferencesValue {
  @override
  Preferences build() =>
      _follow(ref, ref.watch(preferencesStoreProvider), (v) => state = v);
}

// --- Home screen widgets ----------------------------------------------------------

@Riverpod(keepAlive: true)
HomeWidgetStore homeWidgetStore(Ref ref) =>
    _owned(ref, HomeWidgetStore(ref.watch(localSettingsProvider)));

@Riverpod(keepAlive: true, name: 'homeWidgetSettingsProvider')
class HomeWidgetSettingsValue extends _$HomeWidgetSettingsValue {
  @override
  HomeWidgetSettings build() =>
      _follow(ref, ref.watch(homeWidgetStoreProvider), (v) => state = v);
}

// --- Tag filters ----------------------------------------------------------------

@Riverpod(keepAlive: true)
TagFilterStore tagFilterStore(Ref ref) =>
    _owned(ref, TagFilterStore(ref.watch(preferencesStoreProvider)));

/// Holds the filter of [area] for [page] while that page's ViewModel watches it:
/// **a tag filter lasts as long as the page that holds it** — calendar to tasks, wiki
/// to search ends it — unless this device keeps filters (Account → Customize).
///
/// A provider of its own, not `onDispose` in the ViewModel's `build`: that runs on
/// every rebuild, and the filter went with every tap on a tag.
@riverpod
void tagFilterHold(Ref ref, String area, String page) {
  final store = ref.watch(tagFilterStoreProvider);
  // After the page is gone: a provider must not change while the tree is torn down.
  ref.onDispose(() => scheduleMicrotask(() => store.release(area)));
}

@Riverpod(keepAlive: true, name: 'tagFiltersProvider')
class TagFiltersValue extends _$TagFiltersValue {
  @override
  Map<String, Set<String>> build() =>
      _follow(ref, ref.watch(tagFilterStoreProvider), (v) => state = v);
}

// --- Session --------------------------------------------------------------------

/// Whether the session asks the server on start if it still holds. Off for the
/// background sync: it runs on the remembered session and learns from the sync itself
/// whether the token still holds.
@Riverpod(keepAlive: true)
bool sessionHandshakeOnStart(Ref ref) => true;

@Riverpod(keepAlive: true)
SessionStore sessionStore(Ref ref) {
  final store = sessionStoreFor(ref);
  if (ref.watch(sessionHandshakeOnStartProvider)) store.start();
  return store;
}

/// The session over the providers of [ref] — starting at [initial] instead of the
/// remembered session, for the tests.
SessionStore sessionStoreFor(Ref ref, {SessionState? initial}) => _owned(
  ref,
  SessionStore(
    repository: ref.watch(sessionRepositoryProvider),
    preferences: ref.watch(preferencesStoreProvider),
    sync: _SyncForSession(ref),
    // The images in memory go with the media repository.
    dropImages: () => ref.invalidate(mediaRepositoryProvider),
    initial: initial,
  ),
);

class _SyncForSession implements SessionSync {
  _SyncForSession(this._ref);

  final Ref _ref;

  @override
  Future<void> syncLast() => _ref.read(syncRepositoryProvider).syncLast();

  @override
  Future<void> stop() => _ref.read(syncRepositoryProvider).stop();
}

@Riverpod(keepAlive: true, name: 'sessionProvider')
class SessionValue extends _$SessionValue {
  @override
  SessionState build() =>
      _follow(ref, ref.watch(sessionStoreProvider), (v) => state = v);
}

/// The identity of the running session: who, from which device.
///
/// Every query that depends on the signed-in member hooks in here. Without this a
/// `FutureProvider` response survives a change of member: after signing in with a
/// different account the previous one's device list was still showing — without
/// any hint that it was stale.
@Riverpod(keepAlive: true)
String? sessionKey(Ref ref) {
  final session = ref.watch(sessionProvider);
  final member = session.member;
  if (member == null) return null;
  return '${member.id}@${session.session?.deviceId}';
}

// --- Sync -----------------------------------------------------------------------

/// Where the sync stands — for the banner, the shell and every screen that waits for
/// the first pull. Follows the engine synchronously.
@Riverpod(keepAlive: true, name: 'syncStatusProvider')
class SyncStatusValue extends _$SyncStatusValue {
  @override
  SyncStatus build() {
    // Without a server the engine never runs; its status would wait for a first
    // answer that cannot come.
    if (!ref.watch(sessionProvider.select((session) => session.hasServer))) {
      return const SyncStatus.local();
    }
    final repository = ref.watch(syncRepositoryProvider);
    final subscription = repository.statusChanges.listen((status) {
      // A finished run may have brought an item to the server whose share sheet
      // failed a moment ago — fetched again, not left failed (Query.refreshFailed).
      if (status.lastSyncedAt != state.lastSyncedAt &&
          ref.exists(accessRepositoryProvider)) {
        ref.read(accessRepositoryProvider).refreshFailed();
      }
      state = status;
    });
    ref.onDispose(subscription.cancel);
    return repository.status;
  }
}

// --- Demo -----------------------------------------------------------------------

/// The public demo's sample data — only in a demo build.
@Riverpod(keepAlive: true)
Demo demo(Ref ref) => .new(ref);

// --- Web update -----------------------------------------------------------------

/// Whether this runs as a served web app — overridden by the tests.
@Riverpod(keepAlive: true)
bool servedWebApp(Ref ref) => kIsWeb;

@Riverpod(keepAlive: true)
WebUpdateStore webUpdateStore(Ref ref) => _owned(
  ref,
  WebUpdateStore(
    ref.watch(webBuildRepositoryProvider),
    web: ref.watch(servedWebAppProvider),
  ),
);

@Riverpod(keepAlive: true, name: 'webUpdateProvider')
class WebUpdateValue extends _$WebUpdateValue {
  @override
  bool build() =>
      _follow(ref, ref.watch(webUpdateStoreProvider), (v) => state = v);
}

// --- Calendar -------------------------------------------------------------------

@Riverpod(keepAlive: true)
CalendarDayStore calendarDayStore(Ref ref) => _owned(ref, CalendarDayStore());

@Riverpod(keepAlive: true, name: 'calendarDayProvider')
class CalendarDayValue extends _$CalendarDayValue {
  @override
  DateTime build() =>
      _follow(ref, ref.watch(calendarDayStoreProvider), (v) => state = v);
}

@Riverpod(keepAlive: true)
WikiTreeStore wikiTreeStore(Ref ref) => _owned(ref, WikiTreeStore());

@Riverpod(keepAlive: true, name: 'wikiTreeProvider')
class WikiTreeValue extends _$WikiTreeValue {
  @override
  Set<String> build() =>
      _follow(ref, ref.watch(wikiTreeStoreProvider), (v) => state = v);
}

@Riverpod(keepAlive: true)
AreaMemoryStore areaMemoryStore(Ref ref) => _owned(ref, AreaMemoryStore());

@Riverpod(keepAlive: true, name: 'areaMemoryProvider')
class AreaMemoryValue extends _$AreaMemoryValue {
  @override
  Map<int, String> build() =>
      _follow(ref, ref.watch(areaMemoryStoreProvider), (v) => state = v);
}

@Riverpod(keepAlive: true)
TodoSidebarStore todoSidebarStore(Ref ref) => _owned(ref, TodoSidebarStore());

@Riverpod(keepAlive: true, name: 'todoSidebarProvider')
class TodoSidebarValue extends _$TodoSidebarValue {
  @override
  String? build() =>
      _follow(ref, ref.watch(todoSidebarStoreProvider), (v) => state = v);
}
