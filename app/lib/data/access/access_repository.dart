import 'package:flutter/foundation.dart';

import 'dart:convert';

import '../../core/api/generated/export.dart';
import '../../core/api/hiwiski_api.dart';
import '../../core/api/hiwiski_failure.dart';
import '../../core/storage/local_settings.dart';
import '../../core/sync/pending_shares.dart';
import '../../core/sync/sync_engine.dart';
import '../../domain/common/item_ref.dart';
import '../query.dart';
import '../../domain/access/offline_shares.dart';

/// Shares — over REST, and offline from what was seen last.
///
/// Shares themselves carry no owner and no share, so they are not items in the sense
/// of the glossary. Their *consequences* do go through the sync, though — as
/// `access_granted` and `access_revoked`.
///
/// **Offline** the sheet comes from the last one the server sent for this item, and a
/// change waits in [PendingShares] until the next sync run gets through — the same way
/// shares chosen at creation wait. Without a sheet seen before there is nothing to
/// change from: the shares are written as a whole, and a guessed starting point would
/// remove the ones the device does not know.
class AccessRepository {
  AccessRepository({
    required this._api,
    required this._pendingShares,
    required this._settings,
    required this._sync,
  });

  final HiwiskiApi _api;
  final PendingShares _pendingShares;
  final LocalSettings _settings;
  final SyncTrigger _sync;

  // Fetched whenever something shows it, not kept for the session: a share changed on
  // another device is what the server says next time, and a sheet kept from before
  // kept showing edit controls to someone lowered to read — every edit then rejected —
  // or "offline" for good after one failed fetch, until a restart.
  late final _sheets = Query<ItemRef, ShareSheet>(shareSheet);

  /// The share sheet of [target] while it is shown — one request for all that show
  /// it, fetched again after a change here.
  Stream<ShareSheet> watchShareSheet(ItemRef target) => _sheets.watch(target);

  /// After a sync run: a sheet asked for before the server knew its item — just
  /// created here, still in the outbox — failed with "not found" and stayed that way:
  /// no "Add" in the info bar until the screen was opened again.
  void refreshFailed() => _sheets.refreshFailed();

  static String _key(ItemRef target) => '${target.type}/${target.id}';

  ShareSheet? _cached(ItemRef target) {
    final raw = _settings.shareSheets[_key(target)];
    if (raw == null) return null;
    return ShareSheet.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  Future<void> _remember(ItemRef target, ShareSheet sheet) =>
      _settings.setShareSheets({
        ..._settings.shareSheets,
        _key(target): jsonEncode(sheet.toJson()),
      });

  Future<ShareSheet> shareSheet(ItemRef target) async {
    try {
      final sheet = await HiwiskiApi.run(
        () => _api.access.getShares(itemType: target.type, itemId: target.id),
      );
      await _remember(target, sheet);
      return sheet;
    } on HiwiskiFailure catch (failure) {
      if (!failure.isNetwork) rethrow;
      final cached = _cached(target);
      if (cached == null) rethrow;
      // A change made offline is already in it (see [setShares]).
      return cached;
    }
  }

  Future<void> setShares(ItemRef target, List<WriteShare> shares) async {
    try {
      await HiwiskiApi.run(
        () => _api.access.setShares(
          itemType: target.type,
          itemId: target.id,
          body: WriteSharesRequest(shares: shares),
        ),
      );
      // An offline change still waiting for the item is older than this one: sent by
      // the next sync, it would have undone it — Grandma, added again online, lost her
      // access a second time.
      await _pendingShares.discard(itemType: target.type, itemId: target.id);
    } on HiwiskiFailure catch (failure) {
      final cached = _cached(target);
      if (!failure.isNetwork || cached == null) rethrow;
      await _pendingShares.replace(
        itemType: target.type,
        itemId: target.id,
        shares: shares,
      );
      await _remember(target, withOwnShares(cached, shares));
    }
    _sheets.refresh(target);
  }

  /// Sharing right at creation: the item is still on its way through the outbox, so
  /// the shares wait until the server knows it ("New
  /// event", "New calendar").
  Future<void> queueShares({
    required String itemType,
    required String itemId,
    required List<WriteShare> shares,
  }) async {
    if (shares.isEmpty) return;
    await _pendingShares.queue(
      itemType: itemType,
      itemId: itemId,
      shares: shares,
    );
    // Don't wait for the next occasion: the outbox has just received the item.
    try {
      await _sync.syncNow();
    } on HiwiskiFailure catch (failure) {
      // The run reports itself in the sync banner; the shares keep waiting.
      debugPrint('hiwiski: shares wait for the next sync: $failure');
    }
  }
}
