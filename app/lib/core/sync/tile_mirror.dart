import 'package:drift/drift.dart';

import '../api/generated/export.dart';
import '../db/hiwiski_database.dart';
import 'entity_codec.dart';

/// Puts [items] in place of what a kiosk's tiles showed before.
///
/// Only for a database that is nothing but a copy of the server's answer — the
/// kiosk's, in memory, beside the device's own. Nothing in it was changed on this
/// device, so nothing goes into an outbox; the device's own changes go through
/// `LocalWrites`.
Future<void> replaceTiles(HiwiskiDatabase tiles, List<ChangeEnvelope> items) =>
    tiles.transaction(() async {
      for (final TableInfo<Table, Object?> table in [
        tiles.events,
        tiles.calendars,
        tiles.todos,
        tiles.todoLists,
        tiles.wikiPages,
      ]) {
        await tiles.delete(table).go();
      }
      for (final item in items) {
        final codec = entityCodecs
            .where((candidate) => candidate.entityType == item.entityType)
            .firstOrNull;
        if (codec == null) continue;
        await codec.upsert(
          tiles,
          id: item.entityId,
          ownerId: item.ownerId ?? '',
          version: item.version,
          containerId: item.containerId,
          entityKey: item.entityKey,
          fields: item.fields ?? const {},
        );
      }
    });
