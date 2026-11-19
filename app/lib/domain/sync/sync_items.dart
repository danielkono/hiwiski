import 'dart:convert';

// The domain models of this feature, field for field what the local database
// stores. The repository maps its rows onto them: the layers above see these
// classes, never a Drift row.

/// A field where the server kept a different value than this device sent.
class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.field,
    this.mine,
    this.theirs,
    this.base,
    required this.detectedAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String field;
  final String? mine;
  final String? theirs;
  final String? base;
  final DateTime detectedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncConflict &&
          other.id == id &&
          other.entityType == entityType &&
          other.entityId == entityId &&
          other.field == field &&
          other.mine == mine &&
          other.theirs == theirs &&
          other.base == base &&
          other.detectedAt == detectedAt;

  @override
  int get hashCode => Object.hashAll([
    id,
    entityType,
    entityId,
    field,
    mine,
    theirs,
    base,
    detectedAt,
  ]);
}

/// A change waiting in the outbox — or stuck there.
class OutboxChange {
  const OutboxChange({
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    this.containerType,
    this.containerId,
    required this.op,
    required this.fields,
    this.baseVersion,
    this.dependsOn,
    required this.state,
    this.errorCode,
    required this.attempts,
    required this.createdAt,
    this.label,
  });

  final String mutationId;
  final String entityType;
  final String entityId;
  final String? containerType;
  final String? containerId;
  final String op;
  final String fields;
  final int? baseVersion;
  final String? dependsOn;
  final String state;
  final String? errorCode;
  final int attempts;
  final DateTime createdAt;
  final String? label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutboxChange &&
          other.mutationId == mutationId &&
          other.entityType == entityType &&
          other.entityId == entityId &&
          other.containerType == containerType &&
          other.containerId == containerId &&
          other.op == op &&
          other.fields == fields &&
          other.baseVersion == baseVersion &&
          other.dependsOn == dependsOn &&
          other.state == state &&
          other.errorCode == errorCode &&
          other.attempts == attempts &&
          other.createdAt == createdAt &&
          other.label == label;

  @override
  int get hashCode => Object.hashAll([
    mutationId,
    entityType,
    entityId,
    containerType,
    containerId,
    op,
    fields,
    baseVersion,
    dependsOn,
    state,
    errorCode,
    attempts,
    createdAt,
    label,
  ]);
}

/// What sits in `fields` of a stuck change — for the list of rejected changes.
Map<String, dynamic> decodeChangeFields(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

/// Something a backup restore left behind on this device: it had it, and the restored
/// server has it not, or older.
class LeftBehindItem {
  const LeftBehindItem({
    required this.entityType,
    required this.entityId,
    required this.label,
    required this.deleted,
    required this.leftAt,
  });

  final String entityType;
  final String entityId;

  /// Its title or name.
  final String label;

  /// Deleted on this device after the backup — bringing it back deletes it again.
  final bool deleted;
  final DateTime leftAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LeftBehindItem &&
          other.entityType == entityType &&
          other.entityId == entityId &&
          other.label == label &&
          other.deleted == deleted &&
          other.leftAt == leftAt;

  @override
  int get hashCode => Object.hash(entityType, entityId, label, deleted, leftAt);
}
