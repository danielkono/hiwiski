import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/stores.dart';

part 'customize_view_model.g.dart';

/// Account → Customize: how this device behaves.
@immutable
class const CustomizeState({
  /// Whether the tag filters stay set when leaving calendar, tasks or wiki.
  required final bool keepFilters,

  /// Whether losing access clears the device at once instead of locking it.
  required final bool wipeOnAccessLost,

  /// Whether there is access to lose: without a server the device
  /// never signs itself out, and the choice is left out.
  final bool signsOut = true,

  /// Whether ticked-off rows move to the bottom of a task or shopping list.
  required final bool doneLast,

  /// Whether each area keeps the page it was left on.
  required final bool keepAreas,

  /// How many seconds "Undo" is offered after a deletion.
  required final int undoSeconds,

  /// Whether the hint above a filter bar on the phone shows — until learned, or as
  /// the member chose.
  final bool pullHint = true,

  /// Whether texts open formatted for writing rather than as Markdown.
  final bool formattedEditor = true,
});

/// What "Undo" can be offered for, in seconds.
const undoChoices = [4, 8, 15, 30];

@riverpod
class CustomizeViewModel extends _$CustomizeViewModel {
  @override
  CustomizeState build() {
    final keepFilters = ref.watch(
      preferencesProvider.select((p) => p.keepFilters),
    );
    final wipe = ref.watch(
      preferencesProvider.select((p) => p.wipeOnAccessLost),
    );
    final doneLast = ref.watch(preferencesProvider.select((p) => p.doneLast));
    final keepAreas = ref.watch(preferencesProvider.select((p) => p.keepAreas));
    final undoSeconds = ref.watch(
      preferencesProvider.select((p) => p.undoSeconds),
    );
    final pullHint = ref.watch(
      preferencesProvider.select((p) => p.showsPullHint),
    );
    final formattedEditor = ref.watch(
      preferencesProvider.select((p) => p.formattedEditor),
    );
    return CustomizeState(
      signsOut: ref.watch(sessionProvider.select((s) => s.hasServer)),
      keepFilters: keepFilters,
      wipeOnAccessLost: wipe,
      doneLast: doneLast,
      keepAreas: keepAreas,
      undoSeconds: undoSeconds,
      pullHint: pullHint,
      formattedEditor: formattedEditor,
    );
  }

  Future<void> setUndoSeconds(int seconds) =>
      ref.read(preferencesStoreProvider).setUndoSeconds(seconds);

  /// Off, the pages each area was left on are forgotten at once.
  Future<void> setKeepAreas(bool keep) async {
    await ref.read(preferencesStoreProvider).setKeepAreas(keep);
    if (!keep) {
      for (final area in [...ref.read(areaMemoryProvider).keys]) {
        ref.read(areaMemoryStoreProvider).forget(area);
      }
    }
  }

  /// Either way the choice is kept: switched on, the hint stays for good.
  Future<void> setPullHint(bool show) =>
      ref.read(preferencesStoreProvider).setPullHint(show);

  Future<void> setFormattedEditor(bool formatted) =>
      ref.read(preferencesStoreProvider).setFormattedEditor(formatted);

  Future<void> setDoneLast(bool doneLast) =>
      ref.read(preferencesStoreProvider).setDoneLast(doneLast);

  Future<void> setKeepFilters(bool keep) =>
      ref.read(preferencesStoreProvider).setKeepFilters(keep);

  Future<void> setWipeOnAccessLost(bool wipe) =>
      ref.read(preferencesStoreProvider).setWipeOnAccessLost(wipe);
}
