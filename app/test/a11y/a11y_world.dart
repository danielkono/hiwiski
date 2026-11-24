import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderFlex;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:hiwiski/app/data_providers.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/app/stores.dart';
import 'package:hiwiski/components/sync_banner/sync_banner_view_model.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_api.dart';
import 'package:hiwiski/core/common/wire.dart';
import 'package:hiwiski/core/db/hiwiski_database.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/storage/local_settings.dart';
import 'package:hiwiski/core/sync/sync_status.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/domain/board/widget_kinds.dart';
import 'package:hiwiski/domain/calendar/event_draft.dart';
import 'package:hiwiski/domain/common/change.dart';
import 'package:hiwiski/domain/links/link_index.dart';
import 'package:hiwiski/domain/session/session_state.dart';
import 'package:hiwiski/domain/wiki/recipe_fields.dart';
import 'package:hiwiski/domain/wiki/wiki_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// What a screen is measured with.
enum Family {
  /// Something in every area, the server answering — a screen as it looks in use.
  full,

  /// Nothing created yet, the server answering with empty lists: the empty states.
  empty,

  /// Nothing on the device and the server out of reach: the error states.
  offline,
}

/// A family behind a server that answers every call a screen makes — by default with
/// something in every area, so that each screen can be measured as it looks in use,
/// not empty. The ids of what was created are in [ids].
class A11yWorld {
  A11yWorld._(this.db, this.settings, this.api, this.server, this.family);

  final HiwiskiDatabase db;
  final LocalSettings settings;
  final HiwiskiApi api;
  final FakeServer server;
  final Family family;
  final Map<String, String> ids = {};

  /// The id of what was created as [name] — in a family without it, one that does
  /// not exist, so a screen shows what it shows for something gone.
  String id(String name) => ids[name] ?? 'missing-$name';

  static Future<A11yWorld> create({
    SessionState session = annaSession,
    Family family = .full,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await LocalSettings.open();
    final db = HiwiskiDatabase(NativeDatabase.memory());
    final server = FakeServer(family);
    final api = HiwiskiApi(tokens: NoTokens(), baseUrl: _base)
      ..dio.httpClientAdapter = server;
    final world = A11yWorld._(db, settings, api, server, family);
    if (family == .full) await world._seed(session);
    return world;
  }

  List<Override> overrides(SessionState session) => [
    databaseProvider.overrideWithValue(db),
    localSettingsProvider.overrideWithValue(settings),
    hiwikiApi(api),
    deviceTimeZoneProvider.overrideWithValue('Europe/Berlin'),
    sessionAt(session),
    syncStatusProvider.overrideWithValue(_status),
    servedWebAppProvider.overrideWithValue(false),
    syncBannerViewModelProvider.overrideWith(() => _QuietBanner(_status)),
  ];

  SyncStatus get _status => family == .offline ? _offline : _synced;

  static Override hiwikiApi(HiwiskiApi api) =>
      hiwiskiApiProvider.overrideWithValue(api);

  Future<void> _seed(SessionState session) async {
    final container = ProviderContainer(
      retry: noRetry,
      overrides: overrides(session),
    );
    try {
      final todos = container.read(todoRepositoryProvider);
      ids['list'] = await todos.createList(
        name: 'Household',
        kind: ListKinds.standard,
        description: 'Everything around the house.',
      );
      ids['todo'] = await todos.createTodo(
        listId: ids['list']!,
        title: 'Call the plumber',
        description: 'About the kitchen tap.',
        dueDate: DateTime(2026, 10, 24),
        assignees: [anna.id],
      );
      await todos.createTodo(listId: ids['list']!, title: 'Water the plants');
      ids['shopping'] = await todos.createList(
        name: 'Groceries',
        kind: ListKinds.shopping,
      );
      await todos.createTodo(
        listId: ids['shopping']!,
        title: 'Milk',
        amount: 2,
        unit: 'l',
      );
      await todos.createTodo(listId: ids['shopping']!, title: 'Bread');
      ids['kanban'] = await todos.createList(
        name: 'Renovation',
        kind: ListKinds.kanban,
      );
      await todos.createTodo(listId: ids['kanban']!, title: 'Paint the hall');

      final calendar = container.read(calendarRepositoryProvider);
      ids['calendar'] = await calendar.createCalendar(
        name: 'Family',
        colorToken: ColorTokens.green,
      );
      ids['event'] = await calendar.createEvent(
        calendarId: ids['calendar']!,
        draft: EventDraft(
          title: 'Dentist',
          time: TimedEvent(
            DateTime(2026, 10, 23, 10),
            DateTime(2026, 10, 23, 11),
          ),
          location: 'Main Street 1',
          description: 'Bring the card.',
        ),
      );

      final wiki = container.read(wikiRepositoryProvider);
      ids['page'] = await wiki.createPage(title: 'Router');
      ids['subpage'] = await wiki.createPage(
        title: 'Wi-Fi',
        parentId: ids['page'],
      );
      ids['recipe'] = await wiki.createPage(
        title: 'Pancakes',
        kind: PageKinds.recipe,
      );

      ids['mindmap'] = await wiki.createPage(
        title: 'Holiday',
        kind: PageKinds.mindmap,
      );
      final maps = container.read(mindmapRepositoryProvider);
      final sea = await maps.addNode(
        pageId: ids['mindmap']!,
        kind: MindmapKinds.note,
        x: 0,
        y: 0,
        width: 220,
        height: 120,
        text: '## Sea\nSun cream, towels',
        look: {WireFields.color: ColorTokens.teal},
      );
      final hills = await maps.addNode(
        pageId: ids['mindmap']!,
        kind: MindmapKinds.plain,
        x: 360,
        y: 40,
        width: 160,
        height: 40,
        text: 'Hills',
      );
      final holiday = await maps.watchMap(ids['mindmap']!).first;
      await maps.connect(holiday.node(sea)!, holiday.node(hills)!, text: 'or');

      final page = (await wiki.watchPage(ids['page']!).first)!;
      await wiki.updatePage(
        page,
        content:
            'The password is on the box.\n\n'
            '- [ ] Restart it weekly\n'
            '- [x] Update the firmware',
      );
      final recipe = (await wiki.watchPage(ids['recipe']!).first)!;
      await wiki.updatePage(
        recipe,
        content: 'Mix everything, rest for ten minutes.',
        properties: recipeChanges(
          servings: const Change(4),
          ingredients: const [
            Ingredient(label: 'Flour', amount: 200, unit: 'g'),
            Ingredient(label: 'Milk', amount: 300, unit: 'ml'),
          ],
        ),
      );
      await wiki.addComment(
        itemType: EntityTypes.todo,
        itemId: ids['todo']!,
        body: 'The plumber comes on Friday.',
      );

      final boards = container.read(boardRepositoryProvider);
      final dashboard = await boards.ensure(BoardKinds.dashboard);
      ids['dashboard'] = dashboard.id;
      ids['widget'] = await boards.addWidget(
        board: dashboard,
        kind: WidgetKind.clock.id,
        existing: const [],
      );

      final tags = container.read(tagRepositoryProvider);
      ids['tag'] = await tags.createTag('Work');
    } finally {
      container.dispose();
    }
  }

  /// Reads through the repositories, as a screen would — for the items a sheet is
  /// opened with.
  Future<T> read<T>(
    Future<T> Function(ProviderContainer container) read,
  ) async {
    final container = ProviderContainer(
      retry: noRetry,
      overrides: overrides(annaSession),
    );
    try {
      return await read(container);
    } finally {
      container.dispose();
    }
  }

  Future<void> close() => db.close();
}

const _base = 'http://hiwiski.test';

/// The address a wall tablet opens the dashboard with.
const kioskToken = 'kiosk-token';

final _synced = SyncStatus(lastSyncedAt: DateTime(2026, 10, 23, 9));

const _offline = SyncStatus(online: false, lastAttemptFailed: true);

const anna = Member(
  id: 'anna',
  username: 'anna',
  displayName: 'Anna',
  isAdmin: true,
  colorToken: .blue,
  groupIds: ['everyone', 'parents'],
);

const ben = Member(
  id: 'ben',
  username: 'ben',
  displayName: 'Ben',
  isAdmin: false,
  colorToken: .rust,
  groupIds: ['everyone'],
);

const _handshake = Handshake(
  apiVersion: 'v1',
  serverVersion: '2026.1.0',
  minClientVersion: '0',
  setupCompleted: true,
  cleartext: false,
  familyName: 'Berger',
);

/// Anna, the administrator, signed in.
const annaSession = SessionState(
  stage: .signedIn,
  serverAddress: _base,
  handshake: _handshake,
  session: Session(
    member: anna,
    deviceId: 'device-1',
    mustChangePassword: false,
  ),
);

/// The handshake of an instance open to the public: it names its legal pages.
const _publicHandshake = Handshake(
  apiVersion: 'v1',
  serverVersion: '2026.1.0',
  minClientVersion: '0',
  setupCompleted: true,
  cleartext: false,
  familyName: 'Berger',
  legalNoticeUrl: 'https://hiwiski.example.org/impressum',
  privacyUrl: 'https://hiwiski.example.org/datenschutz',
);

/// Anna, signed in to an instance open to the public.
const annaPublicSession = SessionState(
  stage: .signedIn,
  serverAddress: _base,
  handshake: _publicHandshake,
  session: Session(
    member: anna,
    deviceId: 'device-1',
    mustChangePassword: false,
  ),
);

/// Nobody signed in yet, at an instance open to the public.
const signedOutPublicSession = SessionState(
  stage: .signedOut,
  serverAddress: _base,
  handshake: _publicHandshake,
);

/// Ben, who is not the administrator, signed in.
const benSession = SessionState(
  stage: .signedIn,
  serverAddress: _base,
  handshake: _handshake,
  session: Session(
    member: ben,
    deviceId: 'device-2',
    mustChangePassword: false,
  ),
);

/// Anna on a device without a server.
const localSession = SessionState(
  stage: .localOnly,
  session: Session(member: anna, deviceId: 'local', mustChangePassword: false),
);

/// The very first start: no server known, nothing on the device.
const firstStartSession = SessionState(stage: .noServer);

/// Nobody signed in yet, the server known.
const signedOutSession = SessionState(
  stage: .signedOut,
  serverAddress: _base,
  handshake: _handshake,
);

class _QuietBanner extends SyncBannerViewModel {
  _QuietBanner(this._state);

  final SyncStatus _state;

  @override
  Future<SyncBannerState> build() async => SyncBannerState(
    status: _state,
    conflicts: const [],
    webUpdate: false,
    index: LinkIndex.from(const []),
    boards: const {},
  );
}

/// Answers the REST calls the screens make, with one family's worth of data. A call
/// it does not know is answered with 404 and recorded in [unknown], so a screen that
/// shows an error because of the fake can be told apart from one that has one.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.family);

  final Family family;
  final List<String> unknown = [];

  static final _now = DateTime(2026, 10, 23, 9);

  Object? _answer(String method, String path) {
    final get = method == 'GET';
    return switch (path) {
      '/api/v1/handshake' => _handshake,
      '/api/v1/members' when get => const MemberList(members: [anna, ben]),
      '/api/v1/groups' when get => const GroupList(
        groups: [
          Group(
            id: 'everyone',
            name: 'Everyone',
            position: 0,
            memberIds: ['anna', 'ben'],
          ),
          Group(
            id: 'parents',
            name: 'Parents',
            position: 1,
            memberIds: ['anna'],
            iconToken: 'FAMILY',
          ),
        ],
      ),
      '/api/v1/invitations' when get => InvitationList(
        invitations: [
          Invitation(
            id: 'inv-1',
            code: 'K7M2-QX9P',
            expiresAt: DateTime(2026, 10, 26, 9),
            deepLink: 'hiwiski://invite?host=hiwiski.test&code=K7M2-QX9P',
            displayName: 'Grandma',
          ),
        ],
      ),
      '/api/v1/devices' when get => DeviceList(
        devices: [
          Device(
            id: 'device-1',
            memberId: 'anna',
            name: "Anna's iPhone",
            platform: .ios,
            createdAt: DateTime(2026, 9, 23, 9),
            current: true,
            lastSeenAt: _now,
          ),
          Device(
            id: 'device-3',
            memberId: 'anna',
            name: 'Kitchen tablet',
            platform: .android,
            createdAt: DateTime(2026, 8, 24, 9),
            current: false,
            lastSeenAt: DateTime(2026, 10, 21, 9),
          ),
        ],
      ),
      '/api/v1/trash' when get => TrashList(
        retentionDays: 30,
        entries: [
          TrashEntry(
            itemType: EntityTypes.todo,
            itemId: 'gone-1',
            title: 'Old errand',
            entityKey: 'TD-9',
            deletedAt: DateTime(2026, 10, 21, 9),
            remainingDays: 28,
            restorable: true,
            deletedBy: 'anna',
          ),
        ],
      ),
      '/api/v1/admin/settings' when get => const InstanceSettings(
        familyName: 'Berger',
        timezone: 'Europe/Berlin',
      ),
      '/api/v1/admin/backups' when get => BackupList(
        backups: [
          BackupInfo(
            id: 'b1',
            createdAt: DateTime(2026, 10, 22, 9),
            bytes: 204800,
            serverVersion: '2026.1.0',
            schemaVersion: '31',
            reason: .scheduled,
            currentKey: true,
          ),
        ],
        status: const BackupStatus(
          directory: '/data/backup',
          passwordSet: true,
        ),
      ),
      '/api/v1/admin/logs' when get => const LogLines(
        lines: ['2026-10-23 09:00 INFO started'],
      ),
      '/api/v1/catalog/aisles' when get => const AisleList(
        aisles: [
          Aisle(id: 'a1', key: 'DAIRY', position: 0, hidden: false),
          Aisle(id: 'a2', name: 'Bakery', position: 1, hidden: false),
        ],
      ),
      '/api/v1/catalog/products' when get => const ProductList(
        products: [
          Product(id: 'p1', name: 'Milk', aisleId: 'a1', defaultUnit: 'l'),
          Product(id: 'p2', name: 'Bread', aisleId: 'a2'),
        ],
      ),
      _ when path.endsWith('/shares') && get => const ShareSheet(
        itemType: EntityTypes.todoList,
        itemId: 'x',
        mayEdit: true,
        ownerId: 'anna',
        myLevel: .write,
        entries: [
          ShareEntry(
            subjectType: .group,
            subjectId: 'everyone',
            level: .read,
            source: .direct,
          ),
        ],
      ),
      _ when path.endsWith('/revisions/r1') && get => Revision(
        id: 'r1',
        seq: 2,
        title: 'Router',
        createdAt: _now,
        kind: .save,
        content: 'The password is on the box.',
        authorId: 'anna',
      ),
      _ when path.contains('/revisions') && get => RevisionList(
        revisions: [
          Revision(
            id: 'r1',
            seq: 2,
            title: 'Router',
            createdAt: _now,
            kind: .save,
            content: 'The password is on the box.',
            authorId: 'anna',
          ),
        ],
      ),
      _ when path.startsWith('/api/v1/links/') => const LinkList(
        outgoing: [],
        incoming: [],
      ),
      _ when path.startsWith('/api/v1/history/') => History(
        reachesBack: DateTime(2026, 7, 25, 9),
        entries: [HistoryEntry(seq: 1, at: _now, op: .upsert, actorId: 'anna')],
      ),
      '/api/v1/search' => const SearchResult(hits: []),
      '/api/v1/boards/$kioskToken' => const BoardView(
        boardId: 'kiosk-board',
        ownerId: 'anna',
        layout: .grid,
        columns: 4,
        name: 'Hallway',
        widgets: [
          WidgetView(
            id: 'clock',
            kind: 'CLOCK',
            gridX: 0,
            gridY: 0,
            gridW: 2,
            gridH: 1,
            position: 0,
          ),
          WidgetView(
            id: 'lists',
            kind: 'TODO_LISTS',
            gridX: 2,
            gridY: 0,
            gridW: 2,
            gridH: 2,
            position: 1,
          ),
        ],
      ),
      '/api/v1/boards/$kioskToken/content' => const BoardContent(items: []),
      '/api/v1/boards/$kioskToken/ticket' => DashboardTicket(
        ticket: 'ticket',
        expiresAt: DateTime(2026, 10, 23, 10),
      ),
      _ => null,
    };
  }

  /// A family that has only just been set up: Anna alone, nothing made yet.
  Object? _empty(String method, String path) {
    final get = method == 'GET';
    return switch (path) {
      '/api/v1/members' when get => const MemberList(members: [anna]),
      '/api/v1/groups' when get => const GroupList(groups: []),
      '/api/v1/invitations' when get => const InvitationList(invitations: []),
      '/api/v1/devices' when get => DeviceList(
        devices: [
          Device(
            id: 'device-1',
            memberId: 'anna',
            name: "Anna's iPhone",
            platform: .ios,
            createdAt: _now,
            current: true,
            lastSeenAt: _now,
          ),
        ],
      ),
      '/api/v1/trash' when get => const TrashList(
        retentionDays: 30,
        entries: [],
      ),
      '/api/v1/admin/backups' when get => const BackupList(
        backups: [],
        status: BackupStatus(directory: '/data/backup', passwordSet: true),
      ),
      '/api/v1/admin/logs' when get => const LogLines(lines: []),
      '/api/v1/catalog/aisles' when get => const AisleList(aisles: []),
      '/api/v1/catalog/products' when get => const ProductList(products: []),
      _ when path.contains('/revisions') && get => const RevisionList(
        revisions: [],
      ),
      _ when path.startsWith('/api/v1/history/') => History(
        reachesBack: _now,
        entries: const [],
      ),
      '/api/v1/boards/$kioskToken' => const BoardView(
        boardId: 'kiosk-board',
        ownerId: 'anna',
        layout: .grid,
        columns: 4,
        widgets: [],
      ),
      _ => _answer(method, path),
    };
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (family == .offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final answer = family == .empty
        ? _empty(options.method, options.uri.path)
        : _answer(options.method, options.uri.path);
    if (answer == null) {
      unknown.add('${options.method} ${options.uri.path}');
      return ResponseBody.fromString(
        jsonEncode({'code': 'not_found', 'message': 'fake'}),
        404,
        headers: _json,
      );
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(answer))),
      200,
      headers: _json,
    );
  }

  static const _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

/// Every guideline Flutter can measure: contrast of text against what is behind
/// it, tap targets of 48 × 48 (Android) and 44 × 44 (iOS), and a label on every
/// tappable thing. All of them are evaluated before the test fails, so one run names
/// everything a screen is missing.
Future<void> expectAccessible(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  final failures = <String>[];
  for (final guideline in [
    androidTapTargetGuideline,
    iOSTapTargetGuideline,
    labeledTapTargetGuideline,
    textContrastGuideline,
  ]) {
    final result = await guideline.evaluate(tester);
    if (!result.passed) {
      failures.add(
        '${guideline.description}\n${result.reason}\n'
        '${_widgetsOf(tester, result.reason ?? '')}',
      );
    }
  }
  handle.dispose();
  if (failures.isNotEmpty) fail(failures.join('\n\n'));
}

/// The rows and columns whose children do not fit, with the widgets they come from —
/// Flutter's own overflow report names neither once the tree is gone.
String overflowsOf(WidgetTester tester) {
  final lines = <String>[];
  void visit(RenderObject object) {
    if (object is RenderFlex && object.hasSize) {
      final horizontal = object.direction == .horizontal;
      double used = 0;
      object.visitChildren((child) {
        if (child is RenderBox && child.hasSize) {
          used += horizontal ? child.size.width : child.size.height;
        }
      });
      final room = horizontal ? object.size.width : object.size.height;
      if (used > room + 0.5) {
        final creator = object.debugCreator;
        final chain = creator is DebugCreator
            ? creator.element.debugGetCreatorChain(30)
            : '$creator';
        lines.add('  ${(used - room).toStringAsFixed(1)} px: $chain');
      }
    }
    object.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
  return lines.join('\n');
}

/// The widgets behind the semantics nodes a guideline names — the node alone says
/// where on the screen, not where in the code.
String _widgetsOf(WidgetTester tester, String reason) {
  final ids = {
    for (final match in RegExp(r'SemanticsNode#(\d+)').allMatches(reason))
      int.parse(match[1]!),
  };
  final lines = <String>[];
  void visit(RenderObject object) {
    final node = object.debugSemantics;
    if (node != null && ids.remove(node.id)) {
      final creator = object.debugCreator;
      final chain = creator is DebugCreator
          ? creator.element.debugGetCreatorChain(12)
          : '$creator';
      lines.add('  #${node.id}: $chain');
    }
    object.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
  return lines.join('\n');
}

/// The app's frame around [home]: theme, translations, a router — screens ask
/// it whether there is a way back.
Widget a11yApp({
  required List<Override> overrides,
  required Widget home,
  Brightness brightness = .light,
  double textScale = 1,
}) => ProviderScope(
  retry: noRetry,
  overrides: overrides,
  child: MaterialApp.router(
    theme: brightness == .light ? HiwiskiTheme.light() : HiwiskiTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    localizationsDelegates: const [
      L.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: L.supportedLocales,
    locale: const Locale('en'),
    routerConfig: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: home),
        ),
        // Where a screen goes when what it shows is gone — measured as the page
        // left behind, not as go_router's "Page Not Found".
        for (final area in ['/calendar', '/tasks', '/wiki', '/account'])
          GoRoute(path: area, builder: (_, _) => const Scaffold()),
      ],
    ),
  ),
);

const _wakelock =
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

/// Answers the plugins screens call without a device behind them: the wall tablet
/// keeps its screen on, and the about page reads the app's version.
void mockPlugins() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(
        _wakelock,
        (_) async => const StandardMessageCodec().encodeMessage(<Object?>[]),
      );
  // A development build: no version, no build number.
  PackageInfo.setMockInitialValues(
    appName: 'Hiwiski',
    packageName: 'de.danielkononov.hiwiski',
    version: '',
    buildNumber: '',
    buildSignature: '',
  );
}

void unmockPlugins() => TestDefaultBinaryMessengerBinding
    .instance
    .defaultBinaryMessenger
    .setMockMessageHandler(_wakelock, null);
