import 'dart:async';

import '../store.dart';
import 'web_build_repository.dart';

/// Whether the server serves another web app than the one running in this tab — after
/// an update, a tab left open keeps the old app until it is reloaded, and the old app
/// does not know the new server's fields.
///
/// The running build is what the server served when the app started — the app creates
/// this store at page load: the app's files are sent with `no-cache`, so the page and
/// `build.json` are of the same build. Asked again on every return to the tab and
/// every quarter of an hour.
class WebUpdateStore extends Store<bool> {
  /// [web]: whether there is a served web app to compare with — only in the browser.
  WebUpdateStore(this._builds, {required this.web}) : super(false) {
    // On a device there is no served web app to compare with — and no timer that
    // could never find anything.
    if (!web) return;
    _timer = Timer.periodic(
      _interval,
      (_) =>
          // A failed check is the same as no update; the next one comes.
          check().ignore(),
    );
    // A failed check is the same as no update; the next one comes.
    check().ignore();
  }

  final WebBuildRepository _builds;
  final bool web;

  static const _interval = Duration(minutes: 15);

  Timer? _timer;
  String? _running;

  /// Asks the server which build it serves.
  Future<void> check() async {
    if (!web) return;
    final served = await _builds.served();
    if (served == null) return;
    final running = _running ??= served;
    if (served != running) value = true;
  }

  void reload() => _builds.reload();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
