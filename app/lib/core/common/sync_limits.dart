import 'dart:convert';

import 'wire.dart';

/// The server's limits on one value of a mutation ("Limits";
/// `SyncLimits` on the server).
///
/// The server rejects a mutation beyond them with `sync.value_too_large`. Every save
/// of a page that is too long was another outbox entry rejected the same way. A
/// change beyond them is still written on the device — nothing typed is lost — but
/// its outbox entry is **held**: it does not go out until a later change brings the
/// value back within the limit (`Outbox.hold`).
abstract final class SyncLimits {
  /// Characters (UTF-16 code units, as the server counts) in one text.
  static const textChars = 200000;

  /// Entries in one list of ids.
  static const ids = 500;

  /// Characters of one JSON value as encoded.
  static const jsonChars = 256 * 1024;

  /// The code a value beyond a limit gets — from the server, or held here.
  static const valueTooLarge = 'sync.value_too_large';

  /// From this share of [textChars] on, the editor warns.
  static const warnFraction = 0.9;

  /// Keys of a merged map (an event's exceptions). The server counts them after
  /// merging; this device can only count what it sends.
  static const mergedKeys = 5000;

  /// The fields that are lists of ids on the server.
  static const _idFields = {
    WireFields.assignees,
    WireFields.attendees,
    WireFields.tags,
    WireFields.calendarIds,
  };

  /// The first field of [fields] beyond its limit, or `null` if all fit.
  static String? exceeded(Map<String, dynamic> fields) {
    for (final MapEntry(:key, :value) in fields.entries) {
      final within = switch (value) {
        final String text => text.length <= textChars,
        final List<Object?> list when _idFields.contains(key) =>
          list.length <= ids,
        final Map<Object?, Object?> map when key == WireFields.exceptions =>
          map.length <= mergedKeys,
        final List<Object?> json => jsonEncode(json).length <= jsonChars,
        final Map<Object?, Object?> json =>
          jsonEncode(json).length <= jsonChars,
        _ => true,
      };
      if (!within) return key;
    }
    return null;
  }
}
