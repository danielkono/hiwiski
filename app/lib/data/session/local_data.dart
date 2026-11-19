import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../core/api/generated/export.dart';
import '../../core/common/wire.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/storage/image_disk_cache.dart';
import '../../core/storage/local_settings.dart';
import '../../core/sync/local_takeover.dart';

/// **The data on a device belongs to exactly one member.**
///
/// A family computer is shared: Anna signs out, Ben signs in. Without this separation
/// Ben then saw Anna's mirrored lists, events and pages — including ones she never
/// shared with him —, and Anna's not-yet-synced changes would have gone to the server
/// under **his** session.
///
/// That is why the database remembers whom it belongs to (`<member>@<server>`), and it
/// gets cleared
/// - on **sign-out** — afterwards nothing of whoever left remains on the device;
/// - when a session starts for **someone other** than the one the data belongs to —
///   the safety net in case a session ended without sign-out (token revoked, device
///   locked out, browser storage half cleared);
/// - on a **change of server**.
///
/// **Except for data made without a server**: its owner is
/// `<member>@local`, and it is never cleared by a claim — it is taken over. The
/// member who connects becomes its owner, and what waits in the outbox goes to their
/// server.
class LocalData {
  LocalData({required this._db, required this._settings})
    : _takeover = LocalTakeover(_db);

  /// The server part of the owner of data made without a server.
  static const serverless = 'local';

  final HiwiskiDatabase _db;
  final LocalSettings _settings;
  final LocalTakeover _takeover;

  /// The claim or wipe under way, if any.
  Future<void>? _claiming;

  /// Clears up if the data belongs to someone else, and writes the new owner.
  /// Call before the first screen — otherwise it shows the other person's data for
  /// one frame.
  ///
  /// **One at a time.** The sync and the session's confirmation both claim at the
  /// start; side by side, both saw no owner, and the second threw away what the sync
  /// had pulled in between.
  ///
  /// Returns whether someone else's data was cleared — the remembered session and the
  /// images in memory went with it, and whoever claimed has to put them back.
  Future<bool> claimFor({required String memberId, required String server}) =>
      _inTurn(() => _claim(memberId: memberId, server: server));

  /// After whatever claim or wipe came first.
  Future<T> _inTurn<T>(Future<T> Function() step) {
    final next = (_claiming ?? Future<void>.value()).then((_) => step());
    _claiming = next.then<void>((_) {}).onError<Object>((_, _) {});
    return next;
  }

  Future<bool> _claim({
    required String memberId,
    required String server,
  }) async {
    final db = _db;
    final owner = '$memberId@$server';
    // Reading the owner, clearing and writing the new one in one transaction: the
    // lock above serializes this isolate only, and the background sync runs in
    // another with its own connection. Its writes now land before or after a claim,
    // not in the middle of one.
    final wiped = await db.transaction(() async {
      final current = await db.owner;
      if (current == owner) return false;
      if (_serverlessMember(current) case final local?) {
        await _takeOver(local, memberId: memberId);
        await db.setOwner(owner);
        return false;
      }
      if (current == null) {
        // New, or from a version before this separation — then it is unknown whom
        // the mirror belongs to. It goes; the next sync fetches it again. **The queue
        // stays**: deleting unsaved work after an update would be the worst trap of an
        // offline app, and whoever wrote it is, as a rule, the one signing in again
        // right now.
        await db.discardMirroredData();
        await db.setOwner(owner);
        return false;
      }
      await db.wipeForNextMember();
      await db.setOwner(owner);
      return true;
    });
    if (wiped) await _clearBesidesTheDatabase();
    return wiped;
  }

  /// The member made without a server whom [owner] names, if it names one.
  static String? _serverlessMember(String? owner) {
    if (owner == null) return null;
    final (member, server) = switch (owner.lastIndexOf('@')) {
      -1 => (owner, ''),
      final at => (owner.substring(0, at), owner.substring(at + 1)),
    };
    return server == serverless ? member : null;
  }

  /// The data made without a server becomes [memberId]'s on a server: compacted
  /// into what goes out, the trash left behind — it does not move along —, and
  /// rewritten to the account the device signed in to if that is not the member it
  /// made itself.
  Future<void> _takeOver(String local, {required String memberId}) async {
    await _takeover.compact(deletedBefore: clock.now());
    if (local != memberId) {
      await _takeover.rewriteMember(local, memberId);
      await _takeover.yieldToExistingAccount();
    }
  }

  /// Keeps [member] in the device's family — without a server it is the only place
  /// the family is known.
  Future<void> keepMember(Member member) => _db
      .into(_db.members)
      .insertOnConflictUpdate(
        MemberRow(
          id: member.id,
          username: member.username,
          displayName: member.displayName,
          colorToken: member.colorToken.json ?? ColorTokens.slate,
          isAdmin: member.isAdmin,
          avatarImageId: member.avatarImageId,
        ),
      );

  /// Compacts what waits in the outbox of a device used without a server — on every
  /// start, so it stays about as large as the data.
  Future<void> compactServerless() => _inTurn(
    () => _takeover.compact(
      deletedBefore: clock.now().toUtc().subtract(LocalTakeover.trashRetention),
    ),
  );

  /// Everything that belongs to a member, off the device.
  ///
  /// In turn with the claims: a claim under way when someone signs out would otherwise
  /// finish after the wipe and write the departed member back as the owner.
  Future<void> wipe() => _inTurn(_wipe);

  /// Whether anything of a member is on the device.
  Future<bool> holdsData() async =>
      await _db.owner != null || _settings.lastSession != null;

  Future<void> _wipe() async {
    await _db.wipeForNextMember();
    await _clearBesidesTheDatabase();
  }

  /// What of a member lives outside the database: settings and cached images.
  Future<void> _clearBesidesTheDatabase() async {
    await _settings.clearMemberData();
    try {
      await ImageDiskCache.clear();
    } catch (error) {
      // A cache that cannot be cleared does not hold up a session.
      debugPrint('hiwiski: image cache not cleared: $error');
    }
  }
}
