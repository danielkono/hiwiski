import 'package:flutter/widgets.dart';

/// The keys the tests find this area's widgets by.
abstract final class CoreKeys {
  static const linkPreviewOpen = ValueKey('link-preview-open');
  static const linkShowAll = ValueKey('link-show-all');
  static const editSave = ValueKey('edit-save');
  static const editCancel = ValueKey('edit-cancel');
  static const webUpdate = ValueKey('web-update');
  static const archiveAction = ValueKey('archive-action');
  static const archiveOnlyThis = ValueKey('archive-only-this');
  static const archiveWithSubpages = ValueKey('archive-with-subpages');
  static const archivedBanner = ValueKey('archived-banner');
  static const archivedChip = ValueKey('archived-chip');
  static const linkSearch = ValueKey('link-search');
  static const recurrenceCount = ValueKey('recurrence-count');
  static const recurrenceInterval = ValueKey('recurrence-interval');
  static const inviteServerDialog = ValueKey('invite-server-dialog');
  static const inviteServerConnect = ValueKey('invite-server-connect');

  static const _conflict = 'conflict-';
  static ValueKey<String> conflict(String id) => .new('$_conflict$id');
}
