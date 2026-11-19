import 'package:clock/clock.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'event_stream.dart';

/// SSE over a streamed HTTP response.
class EventStreamImpl implements EventStream {
  HttpClient? _client;
  StreamSubscription<String>? _subscription;
  Timer? _watchdog;

  /// The server sends a heartbeat every 25 seconds. Nothing for this long, and the
  /// connection is taken for dead: one that dies without a word — a Wi-Fi switch, a
  /// router forgetting it — otherwise sat open for a long time, and no signal came.
  static const _silence = Duration(seconds: 60);

  @override
  Stream<int> connect({
    required String baseUrl,
    required String ticket,
    void Function(bool running)? onRestoring,
  }) {
    final controller = StreamController<int>();

    () async {
      try {
        final client = HttpClient();
        _client = client;
        final request = await client.getUrl(
          Uri.parse(
            '$baseUrl${EventStreamWire.path}?${EventStreamWire.ticketParam}=$ticket',
          ),
        );
        request.headers.set(
          HttpHeaders.acceptHeader,
          EventStreamWire.contentType,
        );
        final response = await request.close();

        DateTime lastLine = clock.now();
        // The event the next data line belongs to.
        String? event;
        _watchdog = Timer.periodic(_silence ~/ 4, (_) {
          if (clock.now().difference(lastLine) < _silence) return;
          // Ends the stream like a dropped connection: the sync reconnects.
          close();
          if (controller.isClosed) return;
          // Closing a stream nobody listens to any more has nothing to report.
          controller.close().ignore();
        });

        _subscription = response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                lastLine = clock.now();
                // Only the data lines count -- and the one event that is not a
                // sequence number. Comments are the heartbeat every 25 seconds -- they
                // keep the connection open and nothing else.
                if (line.trim() ==
                    '${EventStreamWire.eventLine}${EventStreamWire.revokedEvent}') {
                  controller.addError(const StreamRevoked());
                  return;
                }
                if (line.startsWith(EventStreamWire.eventLine)) {
                  event = line
                      .substring(EventStreamWire.eventLine.length)
                      .trim();
                  return;
                }
                if (line.startsWith(EventStreamWire.dataLine)) {
                  final data = line
                      .substring(EventStreamWire.dataLine.length)
                      .trim();
                  if (event == EventStreamWire.restoringEvent) {
                    onRestoring?.call(data == EventStreamWire.restoringRunning);
                    return;
                  }
                  final seq = int.tryParse(data);
                  if (seq != null) controller.add(seq);
                }
              },
              onDone: controller.close,
              onError: controller.addError,
              cancelOnError: true,
            );
      } catch (error) {
        controller.addError(error);
        await controller.close();
      }
    }();

    controller.onCancel = close;
    return controller.stream;
  }

  @override
  void close() {
    _watchdog?.cancel();
    _watchdog = null;
    _subscription?.cancel();
    _subscription = null;
    _client?.close(force: true);
    _client = null;
  }
}
