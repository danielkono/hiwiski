import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/stores.dart';

part 'shell_view_model.g.dart';

/// The shell around every screen: the drawer, the family's name, and whether the
/// first sync is still under way.
@immutable
class const ShellState({
  /// Whether the drawer on a wide screen shows its labels — remembered per device.
  required final bool drawerExpanded,
  required final String familyName,

  /// In the browser nothing is on the device before the first pull. `online`: after a
  /// failed attempt, further background attempts do not show the spinner again —
  /// otherwise it would flicker every fifteen seconds.
  required final bool waitingForFirstSync,

  /// Where each area was left, by its index — empty while areas do not keep their
  /// page (Account → Customize).
  final Map<int, String> areaLocations = const {},

  /// Whether there is a family to open — on a server; without one the
  /// device's member is all there is.
  final bool hasFamily = true,

  /// A backup is being restored on the server: the app shows it and takes no
  /// changes until it is done — after a restart of the app, too.
  final bool restoring = false,

  /// Whether the filter bars on the phone show their hint ("Pull for filters").
  final bool showPullHint = true,
});

@riverpod
class ShellViewModel extends _$ShellViewModel {
  @override
  ShellState build() => .new(
    hasFamily: ref.watch(sessionProvider.select((s) => s.hasServer)),
    restoring: ref.watch(sessionProvider.select((s) => s.restoring)),
    showPullHint: ref.watch(preferencesProvider.select((p) => p.showsPullHint)),
    drawerExpanded: ref.watch(
      preferencesProvider.select((p) => p.drawerExpanded),
    ),
    familyName: ref.watch(
      sessionProvider.select((s) => s.handshake?.familyName ?? ''),
    ),
    areaLocations: ref.watch(preferencesProvider.select((p) => p.keepAreas))
        ? ref.watch(areaMemoryProvider)
        : const {},
    waitingForFirstSync: ref.watch(
      syncStatusProvider.select(
        (status) =>
            status.syncing && status.online && status.lastSyncedAt == null,
      ),
    ),
  );

  /// The area [area] is left at [location] — to return there when it is chosen again.
  void leaveArea(int area, String location) {
    if (!ref.read(preferencesProvider).keepAreas) return;
    ref.read(areaMemoryStoreProvider).remember(area, location);
  }

  /// [area] chosen while in it: back to its start, and nothing to return to.
  void resetArea(int area) => ref.read(areaMemoryStoreProvider).forget(area);

  /// A filter bar was pulled down while its hint was showing.
  Future<void> recordPull() => ref.read(preferencesStoreProvider).recordPull();

  Future<void> toggleDrawer() =>
      ref.read(preferencesStoreProvider).toggleDrawer();
}
