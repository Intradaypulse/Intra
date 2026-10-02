import 'dart:collection';

class LruFutureCache<K, V> {
  LruFutureCache({required this.capacity})
    : assert(capacity > 0, 'capacity must be positive');

  final int capacity;
  final LinkedHashMap<K, Future<V>> _items = LinkedHashMap<K, Future<V>>();

  final Map<K, void Function()> _discard = {};

  int get length => _items.length;

  Future<V> getOrCreate(K key, Future<V> Function() loader, {void Function()? onDiscard}) {
    final existing = _items.remove(key);
    if (existing != null) {
      _items[key] = existing;
      return existing;
    }

    late final Future<V> value;
    value = Future<V>.sync(loader).then(
      (result) => result,
      onError: (Object error, StackTrace stack) {
        // Failed renders must be retryable; an older failure cannot evict a
        // replacement inserted after clear/remove.
        if (identical(_items[key], value)) remove(key);
        Error.throwWithStackTrace(error, stack);
      },
    );
    _items[key] = value;
    if (onDiscard != null) _discard[key] = onDiscard;
    while (_items.length > capacity) {
      remove(_items.keys.first);
    }
    return value;
  }

  void remove(K key) {
    _items.remove(key);
    _discard.remove(key)?.call();
  }
  void clear() {
    for (final key in _items.keys.toList()) { remove(key); }
  }
}
