import 'dart:async';

import 'event_stream_stub.dart'
    if (dart.library.io) 'event_stream_io.dart'
    if (dart.library.js_interop) 'event_stream_web.dart';

/// The real-time stream.
///
/// **The signal carries no data**, only the sequence number. Each signal triggers a
/// normal, share-filtered pull; a missed one cannot break anything.
///
/// Two implementations, because there is no common one: in the browser Dio cannot read
/// a running stream, hence `EventSource`; on the other platforms a streamed response.
/// Both talk to the same endpoint.
/// The device was signed out — from itself or from another device. Reported as the
/// stream's error; the stream ends with it.
/// The vocabulary of the event stream.
abstract final class EventStreamWire {
  static const path = '/api/v1/events';

  /// The browser cannot send a header with `EventSource` — hence a query parameter.
  static const ticketParam = 'ticket';
  static const contentType = 'text/event-stream';

  /// The events: a new sequence number, or the end of this reader's access.
  static const seqEvent = 'seq';
  static const revokedEvent = 'revoked';

  /// A backup is being restored (`true`), or is done (`false`).
  static const restoringEvent = 'restoring';
  static const restoringRunning = 'true';

  /// The prefixes of the lines in the raw stream.
  static const eventLine = 'event:';
  static const dataLine = 'data:';
}

class StreamRevoked implements Exception {
  const StreamRevoked();
}

abstract class EventStream {
  /// Connects and reports every new sequence number — and [StreamRevoked] as an
  /// error once this device has been signed out.
  ///
  /// [ticket] can be redeemed once and is valid for 60 seconds: `EventSource` in the
  /// browser cannot send a header, and the endpoint still must not be open — it would
  /// reveal *that* something has changed.
  ///
  /// [onRestoring] hears when a backup restore begins (`true`) and ends (`false`): every
  /// app shows it at once, not only the one that started it.
  Stream<int> connect({
    required String baseUrl,
    required String ticket,
    void Function(bool running)? onRestoring,
  });

  void close();

  factory EventStream() = EventStreamImpl;
}
