import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/lru_future_cache.dart';

void main() {
  test('eviction, removal and clear cancel each discarded job once', () async {
    final cache = LruFutureCache<int, int>(capacity: 1);
    final cancelled = <int>[];
    await cache.getOrCreate(1, () async => 1, onDiscard: () => cancelled.add(1));
    await cache.getOrCreate(1, () async => 99, onDiscard: () => cancelled.add(99));
    expect(cancelled, isEmpty);
    await cache.getOrCreate(2, () async => 2, onDiscard: () => cancelled.add(2));
    expect(cancelled, [1]);
    cache.remove(2);
    cache.remove(2);
    await cache.getOrCreate(3, () async => 3, onDiscard: () => cancelled.add(3));
    cache.clear();
    expect(cancelled, [1, 2, 3]);
  });

  test('LRU cache evicts least recently used entry', () async {
    final cache = LruFutureCache<int, String>(capacity: 2);
    var loads = 0;

    Future<String> load(int key) async {
      loads++;
      return 'value-$key';
    }

    expect(await cache.getOrCreate(1, () => load(1)), 'value-1');
    expect(await cache.getOrCreate(2, () => load(2)), 'value-2');
    expect(cache.length, 2);

    // Refresh key 1 so key 2 becomes least recently used.
    expect(await cache.getOrCreate(1, () => load(1)), 'value-1');
    expect(loads, 2);

    expect(await cache.getOrCreate(3, () => load(3)), 'value-3');
    expect(cache.length, 2);

    // Key 2 was evicted and therefore loads again.
    expect(await cache.getOrCreate(2, () => load(2)), 'value-2');
    expect(loads, 4);
  });

  test('failed thumbnail is evicted so a later request can retry', () async {
    final cache = LruFutureCache<int, String>(capacity: 2);
    await expectLater(
      cache.getOrCreate(1, () async => throw StateError('render failed')),
      throwsStateError,
    );
    expect(cache.length, 0);
    expect(await cache.getOrCreate(1, () async => 'retried'), 'retried');
  });

  test('LRU cache clear removes all retained futures', () async {
    final cache = LruFutureCache<int, int>(capacity: 3);
    await cache.getOrCreate(1, () async => 1);
    await cache.getOrCreate(2, () async => 2);
    expect(cache.length, 2);
    cache.clear();
    expect(cache.length, 0);
  });
}
