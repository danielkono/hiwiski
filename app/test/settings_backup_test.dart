import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/app/repositories.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/core/api/hiwiski_failure.dart';
import 'package:hiwiski/core/l10n/generated/app_localizations.dart';
import 'package:hiwiski/core/theme/hiwiski_theme.dart';
import 'package:hiwiski/data/admin/admin_repository.dart';
import 'package:hiwiski/data/session/session_repository.dart';
import 'package:hiwiski/data/sync/sync_repository.dart';
import 'package:hiwiski/features/admin/settings/view/settings_screen.dart';
import 'package:hiwiski/domain/session/session_state.dart';

import 'support/fakes.dart';

/// **A backup says what came of it.** "Back up now" failed silently, could be tapped
/// twice while running, and a restore — which replaces the whole family's data —
/// ended without a word.
void main() {
  Future<_FakeAdmin> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final admin = _FakeAdmin();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...quietSync,
          adminRepositoryProvider.overrideWithValue(admin),
          sessionAt(_session, repository: _Sessions()),
          familyRepositoryProvider.overrideWithValue(NoFamily()),
          syncRepositoryProvider.overrideWithValue(_FakeSync()),
        ],
        child: MaterialApp(
          theme: HiwiskiTheme.light(),
          localizationsDelegates: const [
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return admin;
  }

  testWidgets('a backup runs once at a time and says when it is done', (
    tester,
  ) async {
    final admin = await pump(tester);
    final running = admin.backup = Completer();

    await tester.tap(find.text('Back up now'));
    await tester.pump();
    await tester.tap(find.text('Back up now'));
    await tester.pump();
    expect(admin.started, equals(1));

    running.complete();
    await tester.pumpAndSettle();
    expect(find.text('Backup written.'), findsOneWidget);
  });

  // "abc" went out as nothing: the server kept the old value, and "Saved" showed.
  testWidgets('a day value that is no number is marked, not saved', (
    tester,
  ) async {
    final admin = await pump(tester);
    final trash = find.widgetWithText(TextField, 'Trash (days)');
    await tester.enterText(trash, 'abc');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(admin.saved, isNull);
    expect(find.text('A whole number of days, at least 1'), findsOneWidget);
  });

  testWidgets('an empty time zone is left as it is', (tester) async {
    final admin = await pump(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Europe/Berlin'), '');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(admin.saved, isNotNull);
    expect(admin.saved!.timezone, isNull);
  });

  /// The password comes before the preview, and a wrong one stays in the dialog.
  testWidgets('a restore asks for the password, then shows what comes back', (
    tester,
  ) async {
    final admin = await pump(tester);
    expect(
      find.textContaining('Before the update to 2026.1.0'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'falsch');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('That password does not open this backup.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).last, 'backup-passwort');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 members'), findsOneWidget);
    expect(admin.restored, isEmpty);

    await tester.tap(find.text('Replace everything'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Restored 12 entries'), findsOneWidget);
    expect(admin.restored, equals(['b1 backup-passwort']));
  });

  // Under the password field the sentence was cut off after one line.
  testWidgets("another family's archive is said in full", (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'fremd');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This backup belongs to another family (Familie Sonnenberg). Set up a '
        'new instance and restore it there with the setup wizard.',
      ),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.decoration?.errorText, isNull);
  });

  testWidgets('a failed backup is shown', (tester) async {
    final admin = await pump(tester);
    admin.fail = true;

    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('The server had a problem'), findsOneWidget);
  });
}

const _session = SessionState(stage: .signedIn);

final _backup = BackupInfo(
  id: 'b1',
  createdAt: DateTime(2026, 10, 8),
  bytes: 1,
  serverVersion: 'v',
  schemaVersion: '23',
  reason: .beforeUpdate,
  updateTo: '2026.1.0',
  currentKey: true,
);

class _FakeAdmin implements AdminRepository {
  @override
  Stream<InstanceSettings> watchInstanceSettings() =>
      .value(const InstanceSettings(timezone: 'Europe/Berlin'));

  @override
  Stream<BackupList> watchBackups() => .value(
    BackupList(
      backups: [_backup],
      status: const BackupStatus(directory: '/data/backup', passwordSet: true),
    ),
  );

  final restored = <String>[];
  Completer<void>? restoring;

  @override
  Future<BackupPreview> inspectBackup(
    String id,
    String password, {
    bool uploaded = false,
  }) async {
    if (password == 'fremd') {
      throw const HiwiskiFailure(
        code: FailureCodes.backupOtherFamily,
        params: {FailureCodes.paramFamilyName: 'Familie Sonnenberg'},
      );
    }
    if (password != 'backup-passwort') {
      throw const HiwiskiFailure(code: FailureCodes.backupPasswordWrong);
    }
    return BackupPreview(
      createdAt: DateTime(2026, 10, 8),
      serverVersion: '2026.1.0',
      schemaVersion: '036',
      bytes: 1024 * 1024,
      members: 4,
      familyName: 'Familie Probe',
    );
  }

  @override
  Future<RestoreResult> restoreBackup(
    String id,
    String password, {
    bool uploaded = false,
  }) async {
    restored.add('$id $password');
    await restoring?.future;
    return const RestoreResult(instanceId: 'new', rows: 12);
  }

  int started = 0;
  bool fail = false;
  Completer<void>? backup;
  InstanceSettings? saved;

  @override
  Future<InstanceSettings> setInstanceSettings(
    InstanceSettings settings,
  ) async => saved = settings;

  @override
  Future<BackupInfo> createBackup() async {
    started++;
    await backup?.future;
    if (fail) throw const HiwiskiFailure(code: FailureCodes.serverError);
    return _backup;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSync implements SyncRepository {
  @override
  Future<void> syncNow() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The handshake the restore asks once it is done.
class _Sessions implements SessionRepository {
  @override
  Future<Handshake> handshake() async => const Handshake(
    apiVersion: 'v1',
    serverVersion: 'v',
    minClientVersion: 'v',
    setupCompleted: true,
    cleartext: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
