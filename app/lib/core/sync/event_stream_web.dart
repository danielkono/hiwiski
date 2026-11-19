import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'event_stream.dart';

/// SSE over `EventSource`.
///
/// The browser cannot send a header with `EventSource` — hence the ticket as a query
/// parameter.
class EventStreamImpl implements EventStream {
  web.EventSource? _source;

  @override
  Stream<int> connect({
    required String baseUrl,
    required String ticket,
    void Function(bool running)? onRestoring,
  }) {
    final controller = StreamController<int>();
    final source = web.EventSource(
      '$baseUrl${EventStreamWire.path}?${EventStreamWire.ticketParam}=$ticket',
    );
    _source = source;

    source.addEventListener(
      EventStreamWire.seqEvent,
      ((web.Event event) {
        final seq = int.tryParse(
          (event as web.MessageEvent).data.dartify()?.toString() ?? '',
        );
        if (seq != null) controller.add(seq);
      }).toJS,
    );
    source.addEventListener(
      EventStreamWire.restoringEvent,
      ((web.Event event) => onRestoring?.call(
        (event as web.MessageEvent).data.dartify()?.toString() ==
            EventStreamWire.restoringRunning,
      )).toJS,
    );
    source.addEventListener(
      EventStreamWire.revokedEvent,
      ((web.Event event) {
        controller.addError(const StreamRevoked());
        controller.close();
        close();
      }).toJS,
    );
    source.onerror = ((web.Event event) {
      // The browser reconnects on its own. If the ticket fails on that -- it can be
      // redeemed once --, the stream closes and the sync layer fetches a new one.
      controller.close();
      close();
    }).toJS;

    controller.onCancel = close;
    return controller.stream;
  }

  @override
  void close() {
    _source?.close();
    _source = null;
  }
}
