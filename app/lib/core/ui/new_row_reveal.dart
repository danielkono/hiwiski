import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

/// Brings a row just added into view — a new card at the end of a long column, a
/// new task in a long list: added below the fold it seemed not to have been added.
/// The same for rows a deletion's "Undo" brings back.
///
/// [expect] when the add is sent, with the rows there are now; the next row whose id
/// was not among them is the new one, and [keyOf] gives it the key [reveal] scrolls
/// to. [expectBack] before an "Undo", with the rows it brings back. A row from
/// elsewhere (the sync, another device) is not followed.
class NewRowReveal {
  /// How long an add is waited for: one that failed does not make a row synced in
  /// minutes later jump into view.
  static const _patience = Duration(seconds: 10);

  /// How many frames the list is moved toward the row before giving up.
  static const _attempts = 6;

  final _key = GlobalKey();
  bool Function(String id)? _awaited;
  DateTime? _since;
  String? _target;

  /// An add is on its way; [ids] are the rows before it.
  void expect(Iterable<String> ids) {
    final before = ids.toSet();
    _awaited = (id) => !before.contains(id);
    _since = clock.now();
  }

  /// An "Undo" is on its way; [ids] are the rows it brings back.
  void expectBack(Iterable<String> ids) {
    final back = ids.toSet();
    _awaited = back.contains;
    _since = clock.now();
  }

  /// The key for the row with [id] — only the newest one has it, and keeps it: taken
  /// away, the row would be built anew.
  Key? keyOf(String id) => id == _target ? _key : null;

  /// Looks for the new row — or the first one back — among [ids], in their order,
  /// and scrolls to it once it is laid out. Rows are built as they come into view: while the new one has not been
  /// built, the list behind [position] moves toward it — to its share of the list.
  void reveal(
    List<String> ids, {
    required ScrollPosition? Function() position,
  }) {
    final awaited = _awaited;
    final since = _since;
    if (awaited == null || since == null) return;
    if (clock.now().difference(since) > _patience) {
      _awaited = null;
      return;
    }
    final index = ids.indexWhere(awaited);
    if (index < 0) return;
    _awaited = null;
    _target = ids[index];
    final share = ids.length < 2 ? 1.0 : index / (ids.length - 1);
    _scroll(share, position, _attempts);
  }

  void _scroll(double share, ScrollPosition? Function() position, int left) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _key.currentContext;
      if (context != null && context.mounted) {
        // Nothing waits for the scroll, and it cannot fail.
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ).ignore();
        return;
      }
      final scroll = position();
      if (scroll == null || left == 0) return;
      scroll.jumpTo(
        scroll.minScrollExtent +
            (scroll.maxScrollExtent - scroll.minScrollExtent) * share,
      );
      _scroll(share, position, left - 1);
    });
  }
}
