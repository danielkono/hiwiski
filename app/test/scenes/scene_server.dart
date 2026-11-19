import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:hiwiski/core/api/generated/export.dart';

/// The server behind the scenes that show what only a server has — devices,
/// backups, sharing, invitations, a subscription's preview, a recipe import.
/// It answers those few calls with sample
/// answers in the scene's language and anything else as unreachable, which the app
/// takes for offline.
class SceneServer implements HttpClientAdapter {
  SceneServer({required this.language, required this.me, required this.family});

  final String language;

  /// The demo's own member, the administrator.
  final Member me;

  /// Everyone else in the sample family.
  final List<Member> family;

  bool get _de => language == 'de';

  // Read on every answer, so a test that fixes the clock fixes these dates too.
  static DateTime get _now => clock.now().toUtc();

  /// [days] before now, by the calendar, at [hour] — or now's time of day.
  static DateTime _ago(int days, {int? hour}) => .utc(
    _now.year,
    _now.month,
    _now.day - days,
    hour ?? _now.hour,
    hour == null ? _now.minute : 0,
  );

  /// The children's group: everyone but the first two.
  Group get _kids => .new(
    id: '00000000-0000-7000-8000-0000000000a1',
    name: _de ? 'Kinder' : 'Kids',
    position: 0,
    memberIds: [for (final member in family.skip(1)) member.id],
  );

  Object? _answer(String method, String path) => switch ((method, path)) {
    ('GET', '/api/v1/members') => MemberList(members: [me, ...family]),
    ('GET', '/api/v1/groups') => GroupList(groups: [_kids]),
    ('GET', '/api/v1/invitations') => const InvitationList(invitations: []),
    ('POST', '/api/v1/invitations') => Invitation(
      id: '00000000-0000-7000-8000-0000000000b1',
      code: 'K7QM-2XPA',
      expiresAt: _ago(-1),
      deepLink: 'https://hiwiski.example/invitation?code=K7QM-2XPA',
    ),
    ('GET', '/api/v1/devices') => DeviceList(devices: _devices),
    ('GET', '/api/v1/admin/settings') => InstanceSettings(
      familyName: _de ? 'Familie Sonnenberg' : 'The Sonnenbergs',
      timezone: 'Europe/Berlin',
      trashRetentionDays: 30,
      logRetentionDays: 90,
    ),
    ('GET', '/api/v1/admin/backups') => BackupList(
      backups: _backups,
      status: BackupStatus(
        directory: '/data/backup',
        passwordSet: true,
        lastBackupAt: _ago(0, hour: 3),
        nextDueAt: _now.add(const Duration(hours: 14)),
      ),
    ),
    ('GET', '/api/v1/admin/logs') => const LogLines(lines: []),
    ('POST', '/api/v1/calendar/subscriptions/preview') => _preview,
    ('POST', '/api/v1/wiki/recipes/import') => _recipe,
    ('GET', final shares)
        when shares.startsWith('/api/v1/items/') &&
            shares.endsWith('/shares') =>
      _shares(shares.split('/')[4], shares.split('/')[5]),
    _ => null,
  };

  List<Device> get _devices => [
    Device(
      id: '00000000-0000-7000-8000-0000000000c1',
      memberId: me.id,
      name: _de ? 'iPhone von ${me.displayName}' : "${me.displayName}'s iPhone",
      platform: .ios,
      createdAt: _ago(210),
      lastSeenAt: _now,
      current: true,
      staySignedIn: true,
    ),
    Device(
      id: '00000000-0000-7000-8000-0000000000c2',
      memberId: me.id,
      name: _de ? 'Laptop im Arbeitszimmer' : 'Laptop in the study',
      platform: .web,
      createdAt: _ago(95),
      lastSeenAt: _now.subtract(const Duration(hours: 5)),
      current: false,
    ),
    Device(
      id: '00000000-0000-7000-8000-0000000000c3',
      memberId: me.id,
      name: _de ? 'Tablet in der Küche' : 'Kitchen tablet',
      platform: .android,
      createdAt: _ago(40),
      lastSeenAt: _ago(2),
      current: false,
      pendingCount: 0,
    ),
  ];

  List<BackupInfo> get _backups => [
    for (final days in const [0, 1, 2, 7])
      BackupInfo(
        id: '00000000-0000-7000-8000-0000000000d$days',
        createdAt: _ago(days, hour: 3),
        bytes: 48000000 - days * 350000,
        serverVersion: '1.4.0',
        schemaVersion: '36',
        reason: days == 2 ? .beforeUpdate : .scheduled,
        updateTo: days == 2 ? '1.4.0' : null,
        currentKey: true,
      ),
  ];

  /// A list shared with the kids, who may tick it off, and with the second parent,
  /// who may write it.
  ShareSheet _shares(String itemType, String itemId) => .new(
    itemType: itemType,
    itemId: itemId,
    mayEdit: true,
    ownerId: me.id,
    myLevel: .write,
    entries: [
      if (family.isNotEmpty)
        ShareEntry(
          subjectType: .member,
          subjectId: family.first.id,
          level: .write,
          source: .direct,
        ),
      ShareEntry(
        subjectType: .group,
        subjectId: _kids.id,
        level: .check,
        source: .direct,
      ),
    ],
  );

  SubscriptionPreview get _preview {
    final year = _now.year;
    DateTime day(int month, int day) => .utc(year, month, day);
    return .new(
      name: _de ? 'Schulferien Baden-Württemberg' : 'School holidays',
      eventCount: 14,
      upcoming: [
        PreviewEvent(
          title: _de ? 'Herbstferien' : 'Autumn half term',
          allDay: true,
          startDate: day(10, 27),
        ),
        PreviewEvent(
          title: _de ? 'Weihnachtsferien' : 'Christmas holidays',
          allDay: true,
          startDate: day(12, 22),
        ),
        PreviewEvent(
          title: _de ? 'Elternabend' : 'Parents’ evening',
          allDay: false,
          startsAt: DateTime.utc(year, 11, 13, 17),
        ),
        PreviewEvent(
          title: _de ? 'Schwimmkurs' : 'Swimming lessons',
          allDay: false,
          startsAt: DateTime.utc(year, 11, 18, 15),
          recurring: true,
        ),
      ],
    );
  }

  ParsedRecipe get _recipe => .new(
    title: _de ? 'Linsensuppe' : 'Lentil soup',
    servings: 4,
    durationMinutes: 45,
    sourceUrl: 'https://rezepte.example/linsensuppe',
    ingredients: [
      for (final (amount, unit, de, en) in const [
        (250, 'g', 'Tellerlinsen', 'brown lentils'),
        (2, null, 'Karotten', 'carrots'),
        (1, null, 'Zwiebel', 'onion'),
        (1, 'l', 'Gemüsebrühe', 'vegetable stock'),
        (2, 'EL', 'Essig', 'vinegar'),
      ])
        ParsedIngredient(
          label: _de ? de : en,
          amount: amount,
          unit: unit,
          uncertain: false,
        ),
      ParsedIngredient(
        label: _de ? 'Salz, Pfeffer' : 'salt, pepper',
        uncertain: true,
      ),
    ],
    content: _de
        ? 'Zwiebel und Karotten würfeln und anschwitzen. Linsen und Brühe dazu, '
              '30 Minuten köcheln lassen. Mit Essig, Salz und Pfeffer abschmecken.'
        : 'Dice the onion and carrots and sweat them. Add lentils and stock and '
              'simmer for 30 minutes. Season with vinegar, salt and pepper.',
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final answer = _answer(options.method, Uri.parse(options.path).path);
    if (answer == null) {
      throw DioException(requestOptions: options, type: .connectionError);
    }
    return .fromString(
      jsonEncode(answer),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
