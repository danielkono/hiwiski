import 'dart:async';

import '../../core/api/generated/export.dart';
import '../../core/api/hiwiski_api.dart';
import '../../core/db/hiwiski_database.dart';
import '../../core/sync/event_stream.dart';
import '../../core/sync/tile_mirror.dart';
import '../../core/api/hiwiski_failure.dart';

/// The dashboard on a wall tablet: a board fetched by its token, without a session
/// — over REST, not through the sync, because the tablet has no member.
class KioskRepository {
  KioskRepository(this._api, this._tiles);

  final HiwiskiApi _api;

  /// What the tiles read: the board's content, apart from this device's own data.
  final HiwiskiDatabase _tiles;

  Future<BoardView> publicBoard(String token) =>
      HiwiskiApi.run(() => _api.dashboard.getPublicBoard(token: token));

  /// Fetches what the board's tiles show — in its owner's name — and puts it in place
  /// of what the tiles showed before.
  ///
  /// The tiles read the same providers as everywhere else. Without this they read the
  /// database of whoever was signed in on the device: on a wall tablet without a
  /// sign-in every data tile was empty, in a browser with someone's session it showed
  /// theirs.
  Future<void> refreshTiles(String token) async {
    final content = await HiwiskiApi.run(
      () => _api.dashboard.getPublicBoardContent(token: token),
    );
    await replaceTiles(_tiles, content.items);
  }

  /// A signal whenever the board changes.
  ///
  /// Listening fetches a ticket and opens the event stream; cancelling closes it. A
  /// ticket the server refuses arrives as the stream's error.
  Stream<int> changes(String token) {
    EventStream? stream;
    StreamSubscription<int>? signals;
    // Cancelled while the ticket was on its way: `isClosed` does not say so, and the
    // stream that connected afterwards was never closed.
    bool cancelled = false;
    late final StreamController<int> controller;
    Future<void> connect() async {
      try {
        final ticket = await HiwiskiApi.run(
          () => _api.dashboard.createDashboardTicket(token: token),
        );
        if (cancelled || controller.isClosed) return;
        final events = stream = EventStream();
        signals = events
            .connect(baseUrl: _api.baseUrl, ticket: ticket.ticket)
            .listen(
              controller.add,
              // The server ended the stream because the address opens nothing any
              // more — regenerated, or the board is gone: said as what loading the
              // board would answer now.
              onError: (Object error) => controller.addError(
                error is StreamRevoked
                    ? const HiwiskiFailure(
                        code: FailureCodes.dashboardBoardNotFound,
                        status: 404,
                      )
                    : error,
              ),
              onDone: controller.close,
            );
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        await controller.close();
      }
    }

    controller = StreamController<int>(
      onListen: () => unawaited(connect()),
      onCancel: () async {
        cancelled = true;
        await signals?.cancel();
        stream?.close();
      },
    );
    return controller.stream;
  }
}
