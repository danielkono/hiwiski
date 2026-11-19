import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/api/generated/export.dart';
import '../../../core/api/hiwiski_failure.dart';

part 'kiosk_view_model.g.dart';

/// What the wall tablet shows: the board, and since when it is unchanged.
@immutable
class const KioskState({
  /// The container the tiles read from: the board's own content, not this device's
  /// data.
  required final ProviderContainer tiles,

  /// `null` until the board has been fetched once.
  final BoardView? board,
  final DateTime? lastUpdate,

  /// The server is gone: the board shown is the last one fetched.
  final bool stale = false,

  /// Why there is no board at all — only when nothing has ever been fetched.
  final String? error,
});

/// The dashboard on a wall tablet, by its token.
///
/// **If the server is gone, whatever was shown last stays up** — an error text in its
/// place would be a step backwards. Only if nothing has ever been loaded is there
/// nothing else to show.
@riverpod
class KioskViewModel extends _$KioskViewModel {
  Timer? _retry;
  StreamSubscription<int>? _events;

  @override
  KioskState build(String token) {
    // Stopped the moment the screen leaves, not only when Riverpod lets go later:
    // the retry timer and the open stream belong to a board that is shown.
    ref
      ..onCancel(_stop)
      ..onResume(() => unawaited(_load()))
      ..onDispose(_stop);
    // After build: the first load sets the state this build has not returned yet.
    Future.microtask(_load);
    return KioskState(tiles: ref.watch(kioskTileContainerProvider));
  }

  Future<void> _load() async {
    final kiosk = ref.read(kioskRepositoryProvider);
    try {
      final board = await kiosk.publicBoard(token);
      // Fetches what the tiles show into the tiles' own database.
      await kiosk.refreshTiles(token);
      if (!ref.mounted) return;
      state = KioskState(
        tiles: state.tiles,
        board: board,
        lastUpdate: clock.now(),
      );
      _listen();
    } on HiwiskiFailure catch (failure) {
      if (!ref.mounted) return;
      // An address that opens nothing any more is not "offline": the old board stays
      // up no longer, the tablet says the address is gone.
      state = state.board == null || failure.status == 404
          ? KioskState(tiles: state.tiles, error: failure.code)
          : KioskState(
              tiles: state.tiles,
              board: state.board,
              lastUpdate: state.lastUpdate,
              stale: true,
            );
      _scheduleRetry();
    }
  }

  /// The stream needs a ticket: an SSE connection cannot send a header along.
  /// The repository fetches it when listening starts.
  ///
  /// **One subscription**, opened after the first load and again only once it has
  /// ended. Every change event used to load and then reconnect: two events close
  /// together raced on the subscription, the loser was never cancelled, and an
  /// always-on tablet collected connections — missing the events in every gap.
  void _listen() {
    if (_events != null) return;
    _events = ref
        .read(kioskRepositoryProvider)
        .changes(token)
        .listen(
          // What changed does not matter here: the board is fetched as a whole
          // anyway, and it is small.
          (_) => unawaited(_load()),
          onError: (Object error) {
            if (error is HiwiskiFailure && error.status == 404) {
              // The address was replaced or the board is gone: said now, not after
              // the next retry.
              unawaited(_events?.cancel());
              _events = null;
              unawaited(_load());
              return;
            }
            // A ticket the server refused: try again later, the board stays.
            if (error is! HiwiskiFailure && ref.mounted) {
              state = KioskState(
                tiles: state.tiles,
                board: state.board,
                lastUpdate: state.lastUpdate,
                stale: true,
              );
            }
            unawaited(_events?.cancel());
            _events = null;
            _scheduleRetry();
          },
          onDone: () {
            _events = null;
            _scheduleRetry();
          },
        );
  }

  void _stop() {
    _retry?.cancel();
    _retry = null;
    unawaited(_events?.cancel());
    _events = null;
  }

  /// Without a stream: check every two minutes.
  ///
  /// A wall tablet must not stay on an old state until the next tap — nobody is
  /// tapping it, after all.
  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(const Duration(minutes: 2), () => unawaited(_load()));
  }
}
