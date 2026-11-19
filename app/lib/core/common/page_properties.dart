import 'dart:convert';

/// A page without properties — an ordinary page.
const emptyProperties = '{}';

/// A page's properties as stored: a JSON object. Broken or missing is empty — a page
/// should not fail to open over one value.
Map<String, Object?> decodeProperties(String raw) {
  if (raw.trim().isEmpty) return const {};
  try {
    return switch (jsonDecode(raw)) {
      final Map<String, Object?> map => map,
      _ => const {},
    };
  } on FormatException {
    return const {};
  }
}

/// [raw] with [changes] laid over it — what a sync or an edit delivers per key. A
/// key set to `null` stays, with `null`: the field is empty, as a column would be.
String mergeProperties(String raw, Map<String, Object?> changes) =>
    jsonEncode({...decodeProperties(raw), ...changes});
