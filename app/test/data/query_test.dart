import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/data/query.dart';

/// **One request however many show it** — and a new one for all of them after a change.
void main() {
  test('watchers of the same key share one fetch', () async {
    int fetched = 0;
    final query = Query<String, int>((_) async => ++fetched);

    final first = query.watch('a').first;
    final second = query.watch('a').first;

    expect(await first, equals(1));
    expect(await second, equals(1));
    expect(fetched, equals(1));
  });

  test('a refresh reaches every watcher', () async {
    int fetched = 0;
    final query = Query<String, int>((_) async => ++fetched);
    final seen = <int>[];
    final subscription = query.watch('a').listen(seen.add);
    await pumpEventQueue();

    query.refresh();
    await pumpEventQueue();

    expect(seen, equals([1, 2]));
    await subscription.cancel();
  });

  test('without keep the next watcher fetches afresh', () async {
    int fetched = 0;
    final query = Query<String, int>((_) async => ++fetched);

    expect(await query.watch('a').first, equals(1));
    expect(await query.watch('a').first, equals(2));
  });

  test('with keep the answer waits for the next watcher', () async {
    int fetched = 0;
    final query = Query<String, int>((_) async => ++fetched, keep: true);

    expect(await query.watch('a').first, equals(1));
    expect(await query.watch('a').first, equals(1));

    // Refreshed while nobody watches: the next watcher fetches.
    query.refresh();
    final seen = <int>[];
    final subscription = query.watch('a').listen(seen.add);
    await pumpEventQueue();
    expect(seen, equals([1, 2]));
    await subscription.cancel();
  });

  test('a failed fetch reaches the watchers as an error', () async {
    final query = Query<String, int>((_) async => throw StateError('offline'));

    await expectLater(query.watch('a').first, throwsStateError);
  });

  test('refreshFailed fetches again only what failed', () async {
    final fails = {'a'};
    int fetched = 0;
    final query = Query<String, int>((key) async {
      fetched++;
      if (fails.contains(key)) throw StateError('not found');
      return fetched;
    });
    final errors = <Object>[];
    final seen = <int>[];
    final a = query.watch('a').listen(seen.add, onError: errors.add);
    final b = query.watch('b').listen((_) {});
    await pumpEventQueue();
    expect(errors, hasLength(1));
    expect(fetched, equals(2));

    // The server knows the item now.
    fails.clear();
    query.refreshFailed();
    await pumpEventQueue();

    expect(seen, equals([3]));
    expect(fetched, equals(3));
    await a.cancel();
    await b.cancel();
  });
}
