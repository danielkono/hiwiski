import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:intl/intl.dart' show DateFormat;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/media/media_repository.dart';
import '../data/access/access_repository.dart';
import '../data/admin/admin_repository.dart';
import '../data/admin/local_trash.dart';
import '../data/app_info/app_info_repository.dart';
import '../data/board/board_repository.dart';
import '../data/board/kiosk_repository.dart';
import '../data/calendar/calendar_repository.dart';
import '../data/calendar/reminder_repository.dart';
import '../data/devices/device_repository.dart';
import '../data/family/family_repository.dart';
import '../data/history/history_repository.dart';
import '../data/search/search_repository.dart';
import '../data/session/local_data.dart';
import '../data/session/session_repository.dart';
import '../data/home_widgets/home_widget_repository.dart';
import '../data/sync/sync_repository.dart';
import '../data/tags/tag_repository.dart';
import '../data/catalog/catalog_repository.dart';
import '../data/todo/todo_repository.dart';
import '../data/update/web_build_repository.dart';
import '../data/wiki/wiki_repository.dart';
import '../core/common/date_patterns.dart';
import '../core/db/hiwiski_database.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../domain/calendar/calendar_reminders.dart';
import 'data_providers.dart';
import 'stores.dart';

part 'repositories.g.dart';

// The repositories — the only providers the business logic may read from the
// composition root. Each one gets its data clients
// handed in; none reads a provider itself.

/// Who creates something now: the owner of every new item. `''` while nobody is
/// signed in.
String _currentMemberId(Ref ref) => ref.read(sessionProvider).member?.id ?? '';

/// How long "Undo" shows on this device — read at each deletion, so a changed
/// setting counts from the next one.
Duration _undoWindow(Ref ref) => ref.read(preferencesProvider).undoWindow;

@Riverpod(keepAlive: true)
TodoRepository todoRepository(Ref ref) => .new(
  db: ref.watch(databaseProvider),
  writes: ref.watch(localWritesProvider),
  currentMemberId: () => _currentMemberId(ref),
  undoWindow: () => _undoWindow(ref),
);

/// Whether a server stands behind the session — the repositories that would ask one
/// are made anew when that changes, and work on the device until then.
bool _serverless(Ref ref) =>
    !ref.watch(sessionProvider.select((session) => session.hasServer));

/// The languages a catalogue seed exists for — the server's; any other
/// gets English.
const _seedLanguages = {'de', 'en'};
const _seedFallback = 'en';
const _seedAsset = 'assets/catalog/products-';
const _seedExtension = '.tsv';

/// The seed in the device's language, as the server keeps it — or in [chosen], the
/// language of the demo's sample data, so its products land in their categories.
Future<String> _catalogSeed(String? chosen) {
  final language = chosen ?? PlatformDispatcher.instance.locale.languageCode;
  final known = _seedLanguages.contains(language) ? language : _seedFallback;
  return rootBundle.loadString('$_seedAsset$known$_seedExtension');
}

/// A reminder's words in the device's language — the language the app shows.
ReminderWords _reminderWords() {
  final locale = PlatformDispatcher.instance.locale;
  final l = lookupL(
    L.supportedLocales.any(
          (supported) => supported.languageCode == locale.languageCode,
        )
        ? Locale(locale.languageCode)
        : _fallbackLocale,
  );
  final language = locale.toLanguageTag();
  return ReminderWords(
    today: l.calToday,
    tomorrow: l.calTomorrow,
    allDay: l.calAllDay,
    date: (day) {
      try {
        return DateFormat(DatePatterns.weekdayDayMonth, language).format(day);
      } on Object catch (_) {
        // The language's date names are not loaded (yet): the numbers alone.
        return DateFormat(DatePatterns.dayMonth).format(day);
      }
    },
  );
}

const _fallbackLocale = Locale('en');

@Riverpod(keepAlive: true)
CatalogRepository catalogRepository(Ref ref) {
  // A new session fetches the catalogue afresh.
  ref.watch(sessionKeyProvider);
  return CatalogRepository(
    db: ref.watch(databaseProvider),
    api: ref.watch(hiwiskiApiProvider),
    settings: ref.watch(localSettingsProvider),
    serverless: _serverless(ref),
    seed: () => _catalogSeed(ref.read(demoProvider).language),
  );
}

@Riverpod(keepAlive: true)
WikiRepository wikiRepository(Ref ref) => .new(
  db: ref.watch(databaseProvider),
  writes: ref.watch(localWritesProvider),
  api: ref.watch(hiwiskiApiProvider),
  currentMemberId: () => _currentMemberId(ref),
  undoWindow: () => _undoWindow(ref),
);

@Riverpod(keepAlive: true)
CalendarRepository calendarRepository(Ref ref) => .new(
  db: ref.watch(databaseProvider),
  writes: ref.watch(localWritesProvider),
  api: ref.watch(hiwiskiApiProvider),
  sync: LazySync(ref),
  currentMemberId: () => _currentMemberId(ref),
  deviceTimeZone: ref.watch(deviceTimeZoneProvider),
);

@Riverpod(keepAlive: true)
ReminderRepository reminderRepository(Ref ref) {
  final repository = ReminderRepository(
    db: ref.watch(databaseProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    timeZone: ref.watch(deviceTimeZoneProvider),
    words: _reminderWords,
  );
  ref.onDispose(repository.dispose);
  return repository;
}

@Riverpod(keepAlive: true)
BoardRepository boardRepository(Ref ref) => .new(
  db: ref.watch(databaseProvider),
  writes: ref.watch(localWritesProvider),
  currentMemberId: () => _currentMemberId(ref),
);

@Riverpod(keepAlive: true)
KioskRepository kioskRepository(Ref ref) =>
    .new(ref.watch(hiwiskiApiProvider), ref.watch(kioskDatabaseProvider));

/// The kiosk's tile content: a database of its own, in memory, never the device's.
@Riverpod(keepAlive: true)
HiwiskiDatabase kioskDatabase(Ref ref) {
  final database = HiwiskiDatabase.memory();
  ref.onDispose(database.close);
  return database;
}

/// The container the kiosk's tiles read from: the same repositories and providers,
/// over [kioskDatabaseProvider] instead of the signed-in device's database. A nested
/// override would not reach them — they do not declare the database as a dependency.
@Riverpod(keepAlive: true)
ProviderContainer kioskTileContainer(Ref ref) {
  // Read only when a tile needs them — a board of clocks needs none.
  final container = ProviderContainer(
    retry: noRetry,
    overrides: [
      databaseProvider.overrideWith((_) => ref.read(kioskDatabaseProvider)),
      localSettingsProvider.overrideWith(
        (_) => ref.read(localSettingsProvider),
      ),
      deviceTimeZoneProvider.overrideWith(
        (_) => ref.read(deviceTimeZoneProvider),
      ),
      hiwiskiApiProvider.overrideWith((_) => ref.read(hiwiskiApiProvider)),
    ],
  );
  ref.onDispose(container.dispose);
  return container;
}

@Riverpod(keepAlive: true)
TagRepository tagRepository(Ref ref) => .new(
  db: ref.watch(databaseProvider),
  writes: ref.watch(localWritesProvider),
  currentMemberId: () => _currentMemberId(ref),
  filters: ref.watch(tagFilterStoreProvider),
);

@Riverpod(keepAlive: true)
SearchRepository searchRepository(Ref ref) => .new(
  db: ref.watch(databaseProvider),
  api: ref.watch(hiwiskiApiProvider),
  serverless: _serverless(ref),
);

// The REST repositories below cache what they fetched (lib/data/query.dart). They are
// tied to the session: switching members throws the answers away.

@Riverpod(keepAlive: true)
HistoryRepository historyRepository(Ref ref) {
  ref.watch(sessionKeyProvider);
  final repository = HistoryRepository(ref.watch(hiwiskiApiProvider));
  // The history is created on the server: fetched again after every sync.
  ref.listen(
    syncStatusProvider.select((status) => status.lastSyncedAt),
    (_, _) => repository.refresh(),
  );
  return repository;
}

@Riverpod(keepAlive: true)
AccessRepository accessRepository(Ref ref) {
  ref.watch(sessionKeyProvider);
  return AccessRepository(
    api: ref.watch(hiwiskiApiProvider),
    pendingShares: ref.watch(pendingSharesProvider),
    settings: ref.watch(localSettingsProvider),
    sync: LazySync(ref),
  );
}

@Riverpod(keepAlive: true)
AdminRepository adminRepository(Ref ref) {
  ref.watch(sessionKeyProvider);
  return AdminRepository(
    ref.watch(hiwiskiApiProvider),
    localTrash: _serverless(ref)
        ? LocalTrash(
            db: ref.watch(databaseProvider),
            writes: ref.watch(localWritesProvider),
          )
        : null,
  );
}

@Riverpod(keepAlive: true)
DeviceRepository deviceRepository(Ref ref) {
  ref.watch(sessionKeyProvider);
  return DeviceRepository(ref.watch(hiwiskiApiProvider));
}

@Riverpod(keepAlive: true)
FamilyRepository familyRepository(Ref ref) {
  ref.watch(sessionKeyProvider);
  return FamilyRepository(
    ref.watch(hiwiskiApiProvider),
    db: ref.watch(databaseProvider),
    serverless: _serverless(ref),
  );
}

@Riverpod(keepAlive: true)
SessionRepository sessionRepository(Ref ref) => .new(
  api: ref.watch(hiwiskiApiProvider),
  tokens: ref.watch(tokenStoreProvider),
  settings: ref.watch(localSettingsProvider),
  localData: LocalData(
    db: ref.watch(databaseProvider),
    settings: ref.watch(localSettingsProvider),
  ),
  localImages: ref.watch(localImageStoreProvider),
);

@Riverpod(keepAlive: true)
HomeWidgetRepository homeWidgetRepository(Ref ref) =>
    .new(ref.watch(homeWidgetBridgeProvider));

@Riverpod(keepAlive: true)
SyncRepository syncRepository(Ref ref) => .new(
  engine: ref.watch(syncEngineProvider),
  outbox: ref.watch(outboxProvider),
  db: ref.watch(databaseProvider),
);

@Riverpod(keepAlive: true)
MediaRepository mediaRepository(Ref ref) {
  // Whoever leaves takes the images in memory along.
  ref.watch(sessionKeyProvider);
  return MediaRepository(
    ref.watch(hiwiskiApiProvider),
    localImages: ref.watch(localImageStoreProvider),
    outbox: ref.watch(outboxProvider),
    serverless: _serverless(ref),
  );
}

@Riverpod(keepAlive: true)
WebBuildRepository webBuildRepository(Ref ref) => const .new();

@Riverpod(keepAlive: true)
AppInfoRepository appInfoRepository(Ref ref) => const .new();
