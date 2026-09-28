import 'dart:collection';

class LruFutureCache<K, V> {
  LruFutureCache({required this.capacity})
      : assert(capacity > 0, 'capacity must be positive');

  final int capacity;
  final LinkedHashMap<K, Future<V>> _items = LinkedHashMap<K, Future<V>>();

  int get length => _items.length;

  Future<V> getOrCreate(K key, Future<V> Function() loader) {
    final existing = _items.remove(key);
    if (existing != null) {
      _items[key] = existing;
      return existing;
    }

    final value = loader();
    _items[key] = value;
    while (_items.length > capacity) {
      _items.remove(_items.keys.first);
    }
    return value;
  }

  void remove(K key) => _items.remove(key);
  void clear() => _items.clear();
}
