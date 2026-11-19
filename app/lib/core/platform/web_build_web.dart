import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Written next to the web app by the server build (`server/app/build.gradle.kts`).
const _buildFile = 'build.json';
const _buildKey = 'build';
const _noStore = 'no-store';

/// The build the server serves right now — `null` if it cannot be told: offline, or a
/// server without `build.json` (a development build).
///
/// Relative, so it resolves against the page's `<base href>` from any deep link, and
/// past every cache: the answer is only worth anything if it is today's.
Future<String?> fetchServedBuild() async {
  try {
    final response = await web.window
        .fetch(_buildFile.toJS, web.RequestInit(cache: _noStore))
        .toDart;
    if (!response.ok) return null;
    final body = (await response.text().toDart).toDart;
    final build = (jsonDecode(body) as Map<String, dynamic>)[_buildKey];
    return build is String && build.isNotEmpty ? build : null;
  } on Object {
    return null;
  }
}

/// Loads the page afresh — the served build instead of the running one.
void reloadPage() => web.window.location.reload();
