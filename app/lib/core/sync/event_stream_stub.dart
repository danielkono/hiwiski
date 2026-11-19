import 'event_stream.dart';

/// Without either platform there is no stream.
///
/// The app still works: without a signal it pulls at startup, after each of its own
/// changes and on backoff. The signal is a shortcut, not a prerequisite.
class EventStreamImpl implements EventStream {
  @override
  Stream<int> connect({
    required String baseUrl,
    required String ticket,
    void Function(bool running)? onRestoring,
  }) => const .empty();

  @override
  void close() {}
}
