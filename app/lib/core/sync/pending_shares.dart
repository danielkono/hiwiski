import 'dart:convert';

import '../api/hiwiski_api.dart';
import '../api/hiwiski_failure.dart';
import '../api/generated/export.dart';
import '../storage/local_settings.dart';
import '../common/wire.dart';

/// Sharing right at creation ("New event",
/// "New calendar").
///
/// A new item is created locally first and travels through the outbox; so the server
/// does not know it yet when the sheet closes. Shares, however, are not a sync subject
/// but a REST call against an existing item. **That is why they wait here** until a
/// sync run has emptied the outbox, and then go out. If the server does not know the
/// item yet (404), they stay; anything else apart from the network is a final no and
/// gets discarded instead of being retried forever.
class PendingShares {
  PendingShares({required this._settings, required this._api});

  static const _shares = 'shares';

  /// How often an entry was answered "no such item".
  static const _misses = 'misses';

  /// Runs with "no such item" after which a share is given up.
  static const _maxMisses = 20;

  final LocalSettings _settings;
  final HiwiskiApi _api;
  bool _flushing = false;

  Future<void> queue({
    required String itemType,
    required String itemId,
    required List<WriteShare> shares,
  }) async {
    if (shares.isEmpty) return;
    await _put(itemType: itemType, itemId: itemId, shares: shares);
  }

  /// A change made offline: it **replaces** whatever still waits for the item —
  /// the shares are written as a whole, so only the last word counts. Unlike
  /// [queue], an empty list goes out too: it removes every own share.
  Future<void> replace({
    required String itemType,
    required String itemId,
    required List<WriteShare> shares,
  }) => _put(itemType: itemType, itemId: itemId, shares: shares);

  Future<void> _put({
    required String itemType,
    required String itemId,
    required List<WriteShare> shares,
  }) async {
    final settings = _settings;
    await settings.setPendingShares([
      for (final raw in settings.pendingShares)
        if (!_isFor(raw, itemType, itemId)) raw,
      jsonEncode({
        WireFields.itemType: itemType,
        WireFields.itemId: itemId,
        _shares: [for (final share in shares) share.toJson()],
      }),
    ]);
  }

  /// Forgets what still waits for an item — its shares were just written online, and
  /// that is the newer word.
  Future<void> discard({
    required String itemType,
    required String itemId,
  }) async {
    final settings = _settings;
    final kept = [
      for (final raw in settings.pendingShares)
        if (!_isFor(raw, itemType, itemId)) raw,
    ];
    if (kept.length != settings.pendingShares.length) {
      await settings.setPendingShares(kept);
    }
  }

  static bool _isFor(String raw, String itemType, String itemId) {
    final entry = jsonDecode(raw) as Map<String, dynamic>;
    return entry[WireFields.itemType] == itemType &&
        entry[WireFields.itemId] == itemId;
  }

  /// Whether any share still waits to go out — from disk, like [flush]: a background
  /// run may have queued one this isolate's copy does not have.
  Future<bool> waiting() async {
    await _settings.reload();
    return _settings.pendingShares.isNotEmpty;
  }

  /// After every run that got the outbox out.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final settings = _settings;
      // From disk, not from this isolate's cache: the app and a background run each
      // keep their own copy, and a share the other one queued was not in it.
      await settings.reload();
      // What went out, or was refused for good. At the end exactly these leave the
      // list — read again then: a share queued or replaced while the calls ran used
      // to be overwritten by the list as it was before them, and was lost.
      final done = <String>{};
      final counted = <String, String>{};
      for (final raw in settings.pendingShares) {
        final entry = jsonDecode(raw) as Map<String, dynamic>;
        if (entry case {
          WireFields.itemType: final String itemType,
          WireFields.itemId: final String itemId,
          _shares: final List<dynamic> shares,
        }) {
          try {
            await HiwiskiApi.run(
              () => _api.access.setShares(
                itemType: itemType,
                itemId: itemId,
                body: WriteSharesRequest(
                  shares: [
                    for (final share in shares)
                      WriteShare.fromJson(share as Map<String, Object?>),
                  ],
                ),
              ),
            );
            done.add(raw);
          } on HiwiskiFailure catch (failure) {
            if (failure.status == 404) {
              // Not known to the server yet — or never: an item whose create was
              // refused and then discarded never arrives, and its share used to be
              // asked about on every sync until the next sign-out. After enough runs
              // without it, it is given up.
              final misses = (entry[_misses] as int? ?? 0) + 1;
              if (misses >= _maxMisses) {
                done.add(raw);
              } else {
                counted[raw] = jsonEncode({...entry, _misses: misses});
              }
            } else if (!failure.isNetwork) {
              done.add(raw);
            }
          }
        } else {
          // Unreadable: it would fail on every sync and never go out — it leaves.
          done.add(raw);
        }
      }
      // Read once more after the calls — from disk again, for the same reason.
      await settings.reload();
      await settings.setPendingShares([
        for (final raw in settings.pendingShares)
          if (!done.contains(raw)) counted[raw] ?? raw,
      ]);
    } finally {
      _flushing = false;
    }
  }
}
