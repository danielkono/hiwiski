import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class AccountKeys {
  static const avatarPick = ValueKey('avatar-pick');
  static const displayName = ValueKey('display-name');
  static const keepFilters = ValueKey('keep-filters');
  static const doneLast = ValueKey('done-last');
  static const keepAreas = ValueKey('keep-areas');
  static const pullHint = ValueKey('pull-hint');
  static const formattedEditor = ValueKey('formatted-editor');
  static const undoSeconds = ValueKey('undo-seconds');
  static const customize = ValueKey('account-customize');
  static const homeWidgets = ValueKey('home-widgets');
  static const _homeWidgetRow = 'home-widget-';
  static ValueKey<String> homeWidgetRow(String kind) =>
      .new('$_homeWidgetRow$kind');
  static const homeWidgetDone = ValueKey('home-widget-done');
  static const homeWidgetRemove = ValueKey('home-widget-remove');
  static const homeWidgetList = ValueKey('home-widget-list');
  static const homeWidgetColumn = ValueKey('home-widget-column');
  static const about = ValueKey('account-about');
  static const packageLicenses = ValueKey('about-package-licenses');
  static const appPrivacy = ValueKey('about-app-privacy');
  static const signOutAcknowledge = ValueKey('sign-out-acknowledge');
  static const signOutConfirm = ValueKey('sign-out-confirm');
  static const accessLostLock = ValueKey('access-lost-lock');
  static const accessLostWipe = ValueKey('access-lost-wipe');
  static const localConnect = ValueKey('local-connect');
  static const localConnectConfirm = ValueKey('local-connect-confirm');
  static const localDelete = ValueKey('local-delete');
  static const localDeleteConfirm = ValueKey('local-delete-confirm');
  static const demoReset = ValueKey('demo-reset');
  static const demoResetConfirm = ValueKey('demo-reset-confirm');
  static const legalNotice = ValueKey('legal-notice');
  static const legalPrivacy = ValueKey('legal-privacy');
}
