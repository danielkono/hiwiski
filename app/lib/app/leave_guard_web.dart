import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.EventListener? _listener;

const _beforeUnload = 'beforeunload';

/// In the browser the queue lives only in memory: closing the tab while a change has not
/// reached the server yet loses it. So the browser asks first — with its own text; it
/// does not allow any other.
void guardLeaving({required bool pending}) {
  if (pending && _listener == null) {
    final listener = ((web.Event event) {
      event.preventDefault();
      (event as web.BeforeUnloadEvent).returnValue = '';
    }).toJS;
    _listener = listener;
    web.window.addEventListener(_beforeUnload, listener);
  } else if (!pending && _listener != null) {
    web.window.removeEventListener(_beforeUnload, _listener);
    _listener = null;
  }
}
