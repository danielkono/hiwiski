import '../common/wire.dart';
import '../l10n/generated/app_localizations.dart';

/// What an item is called in the lists of changes — what did not sync, what a backup
/// restore left behind: its own label, or, without one, its kind of item. A mind
/// map's stroke, picture or unlabelled connection has no words of its own, and its
/// type's code stood there, or nothing. **An unknown type stays visible**, as an
/// unknown field does in the history.
String syncItemLabel(L l, String entityType, String? label) =>
    switch (label?.trim()) {
      final String own when own.isNotEmpty => own,
      _ => switch (entityType) {
        EntityTypes.pinboardNode => l.syncItemPinboardElement,
        EntityTypes.pinboardEdge => l.syncItemPinboardConnection,
        _ => entityType,
      },
    };
