import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class SetupKeys {
  static const displayName = ValueKey('setup.displayName');
  static const setupCode = ValueKey('setup.setupCode');
  static const familyName = ValueKey('setup.familyName');
  static const password = ValueKey('setup.password');
  static const passwordRepeat = ValueKey('setup.passwordRepeat');
  static const timezone = ValueKey('setup.timezone');
  static const username = ValueKey('setup.username');
  static const backupPassword = ValueKey('setup.backupPassword');
  static const backupPasswordRepeat = ValueKey('setup.backupPasswordRepeat');
  static const restorePassword = ValueKey('setup.restorePassword');
  static const startFresh = ValueKey('setup.startFresh');
  static const restoreBackup = ValueKey('setup.restoreBackup');
}
