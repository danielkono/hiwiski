/// What sync is doing right now — for the sync indicator and banner.
class SyncStatus {
  const SyncStatus({
    this.online = true,
    this.syncing = false,
    this.pending = 0,
    this.stuck = 0,
    this.conflicts = 0,
    this.lastSyncedAt,
    this.resyncRequired = false,
    this.lastAttemptFailed = false,
    this.local = false,
  });

  /// Without a server: nothing syncs, nothing waits, nothing is
  /// offline — there is nowhere to sync to.
  const SyncStatus.local() : this(local: true);

  /// The server was reachable on the last attempt.
  ///
  /// "Offline. Everything stays usable, syncing happens later." — the app locks
  /// nothing, it just says so.
  final bool online;

  final bool syncing;

  /// How many changes are still waiting. Shown in the account: "3 changes are waiting
  /// to sync. They will stay."
  final int pending;

  /// How many are stuck — rejected, or blocked by a rejected prerequisite.
  final int stuck;

  final int conflicts;

  final DateTime? lastSyncedAt;

  /// The local state is older than the oldest log entry, or the instance was
  /// restored.
  final bool resyncRequired;

  /// The last run reached the server and failed with an error that is not
  /// "unreachable". Whoever waits for a first answer from the sync takes that as one,
  /// as they take being offline.
  final bool lastAttemptFailed;

  /// The app runs without a server: whoever waits for the sync has their answer —
  /// the device's own data is all there is.
  final bool local;

  /// Whether the sync has given a first answer: a pull, being offline — or a sync
  /// that reached the server and failed. Without the last, a fresh install whose
  /// first sync got a 500 waited with no end.
  bool get answered =>
      local || lastSyncedAt != null || !online || lastAttemptFailed;

  SyncStatus copyWith({
    bool? online,
    bool? syncing,
    int? pending,
    int? stuck,
    int? conflicts,
    DateTime? lastSyncedAt,
    bool? resyncRequired,
    bool? lastAttemptFailed,
    bool? local,
  }) => .new(
    online: online ?? this.online,
    syncing: syncing ?? this.syncing,
    pending: pending ?? this.pending,
    stuck: stuck ?? this.stuck,
    conflicts: conflicts ?? this.conflicts,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    resyncRequired: resyncRequired ?? this.resyncRequired,
    lastAttemptFailed: lastAttemptFailed ?? this.lastAttemptFailed,
    local: local ?? this.local,
  );
}
