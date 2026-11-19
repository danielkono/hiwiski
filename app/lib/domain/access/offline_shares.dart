import '../../core/api/generated/export.dart';

/// The sheet as it will be once [shares] reach the server — what the device shows
/// while they wait (offline).
///
/// The owner and the automatic entries stay. Own shares replace inheritance:
/// with any own share the inherited entries go; without one they
/// stay as last seen.
ShareSheet withOwnShares(ShareSheet sheet, List<WriteShare> shares) =>
    sheet.copyWith(
      entries: [
        for (final entry in sheet.entries)
          if (entry.source == .owner ||
              entry.source == .assigned ||
              (entry.source == .inherited && shares.isEmpty))
            entry,
        for (final share in shares)
          ShareEntry(
            subjectType: share.subjectType,
            subjectId: share.subjectId,
            level: share.level,
            source: .direct,
          ),
      ],
    );
