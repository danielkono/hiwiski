import 'dart:async';

/// An answer fetched from the server, shared by everyone who watches the same key:
/// one request however many screens and components
/// show it, and a new one for all of them after [refresh].
///
/// A new watcher gets the last answer at once. Without [keep] the answer goes when the
/// last watcher does — the next one fetches afresh, as a screen that is opened again
/// should; with it the answer stays for the next watcher, until [refresh].
class Query<K, V> {
  Query(this._fetch, {this.keep = false});

  final Future<V> Function(K key) _fetch;

  /// Whether an answer outlives its watchers.
  final bool keep;

  final _entries = <K, _Entry<V>>{};

  Stream<V> watch(K key) {
    late final StreamController<V> controller;
    controller = StreamController<V>(
      onListen: () {
        final entry = _entries.putIfAbsent(key, _Entry.new);
        entry.watchers.add(controller);
        final last = entry.last;
        if (last != null) controller.add(last.value);
        // Already on its way, it reaches this watcher too.
        if ((last == null && !entry.loading) || entry.stale) _load(key, entry);
      },
      onCancel: () {
        final entry = _entries[key];
        if (entry == null) return;
        entry.watchers.remove(controller);
        if (entry.watchers.isEmpty && !keep) _entries.remove(key);
      },
    );
    return controller.stream;
  }

  /// Fetches again — for [key], or every answer when it is left out. An answer nobody
  /// watches is fetched by its next watcher.
  void refresh([K? key]) {
    final keys = key == null ? [..._entries.keys] : [key];
    for (final k in keys) {
      final entry = _entries[k];
      if (entry == null) continue;
      if (entry.watchers.isEmpty) {
        entry.stale = true;
      } else {
        _load(k, entry);
      }
    }
  }

  /// Fetches again every watched answer whose last fetch failed — an item the server
  /// did not know yet, asked for before the sync had brought it there.
  void refreshFailed() {
    for (final MapEntry(:key, :value) in [..._entries.entries]) {
      if (value.failed && value.watchers.isNotEmpty) _load(key, value);
    }
  }

  Future<void> _load(K key, _Entry<V> entry) async {
    entry.stale = false;
    if (entry.loading) {
      entry.again = true;
      return;
    }
    entry.loading = true;
    try {
      final value = await _fetch(key);
      entry.last = (value: value);
      entry.failed = false;
      for (final watcher in [...entry.watchers]) {
        watcher.add(value);
      }
    } on Object catch (error, stack) {
      entry.failed = true;
      for (final watcher in [...entry.watchers]) {
        watcher.addError(error, stack);
      }
    } finally {
      entry.loading = false;
    }
    if (entry.again) {
      entry.again = false;
      await _load(key, entry);
    }
  }
}

class _Entry<V> {
  final watchers = <StreamController<V>>[];
  ({V value})? last;
  bool loading = false;
  bool again = false;
  bool stale = false;
  bool failed = false;
}
