/// The timestamp inside a UUIDv7.
///
/// **UUIDv7 is assigned on the device so things can be created offline** — and
/// it carries its creation time in the first 48 bits. So "5 minutes ago" on a comment
/// needs neither a column of its own nor a server response: the time has been there
/// since the identifier was assigned.
///
/// Returns `null` if the identifier is not a v7 — older data or an identifier assigned
/// elsewhere must not cost the display.
DateTime? timeOfUuidV7(String id) {
  final hex = id.replaceAll('-', '');
  if (hex.length != 32) return null;
  // The version sits in the 13th nibble.
  if (hex[12] != '7') return null;
  final millis = int.tryParse(hex.substring(0, 12), radix: 16);
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}
