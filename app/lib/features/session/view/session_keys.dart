import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class SessionKeys {
  static const signInAgain = ValueKey('sign-in-again');
  static const discardData = ValueKey('discard-data');
  static const discardConfirm = ValueKey('discard-confirm');
  static const backToLock = ValueKey('back-to-lock');
  static const loginUsername = ValueKey('login-username');
  static const startLocal = ValueKey('start-local');
  static const localName = ValueKey('local-name');
  static const localStartConfirm = ValueKey('local-start-confirm');
}
