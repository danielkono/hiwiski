import '../../core/common/sync_limits.dart';

/// How a text stands against the server's limit for one text.
enum TextLength {
  fits,

  /// From [SyncLimits.warnFraction] of the limit on: the editor warns.
  nearLimit,

  /// Beyond it: saved on the device, but its change does not sync until it is shorter.
  overLimit,
}

/// Where [text] stands — counted in UTF-16 code units, as the server counts.
TextLength textLengthOf(String text) {
  final length = text.length;
  if (length > SyncLimits.textChars) return .overLimit;
  if (length >= SyncLimits.textChars * SyncLimits.warnFraction) {
    return .nearLimit;
  }
  return .fits;
}
