import 'dart:collection';

typedef LruRemove<V> = void Function(V value);

/// An implementation of a [Map] which has a maximum size and uses a [Least
/// Recently Used](http://en.wikipedia.org/wiki/Cache_algorithms#LRU) algorithm
/// to remove items from the [Map] when the [maximumSize] is reached and new
/// items are added.
///
/// It is safe to access the [keys] and [values] collections without affecting
/// the "used" ordering - as well as using [forEach]. Other types of access,
/// including bracket, and [putIfAbsent], promotes the key-value pair to the
/// MRU position.
abstract class LruMap<K, V> implements Map<K, V> {
  /// Creates a [LruMap] instance with the default implementation.
  factory LruMap({int? maximumSize, LruRemove<V>? onLruRemove}) =
      LinkedLruHashMap<K, V>;

  /// Maximum size of the [Map]. If [length] exceeds this value at any time, n
  /// entries accessed the earliest are removed, where n is [length] -
  /// [maximumSize].
  int? get maximumSize;

  set maximumSize(int? size);
}

/// Simple implementation of a linked-list entry that contains a [key] and
/// [value].
class _LinkedEntry<K, V> {
  _LinkedEntry(this.key, this.value);

  K key;
  V value;

  _LinkedEntry<K, V>? next;
  _LinkedEntry<K, V>? previous;
}

/// A linked hash-table based implementation of [LruMap].
class LinkedLruHashMap<K, V> implements LruMap<K, V> {
  /// Create a new LinkedLruHashMap with a [maximumSize].
  factory LinkedLruHashMap({int? maximumSize, LruRemove<V>? onLruRemove}) =>
      LinkedLruHashMap._fromMap(HashMap<K, _LinkedEntry<K, V>>(),
          maximumSize: maximumSize, onLruRemove: onLruRemove);

  LinkedLruHashMap._fromMap(this._entries,
      {int? maximumSize, LruRemove<V>? onLruRemove})
      // This pattern is used instead of a default value because we want to
      // be able to respect null values coming in from MapCache.lru.
      : _maximumSize = maximumSize,
        _onLruRemove = onLruRemove;

  final Map<K, _LinkedEntry<K, V>> _entries;

  int? _maximumSize;
  LruRemove<V>? _onLruRemove;

  _LinkedEntry<K, V>? _head;
  _LinkedEntry<K, V>? _tail;

  /// Adds all key-value pairs of [other] to this map.
  ///
  /// The operation is equivalent to doing `this[key] = value` for each key and
  /// associated value in [other]. It iterates over [other], which must
  /// therefore not change during the iteration.
  ///
  /// If a key of [other] is already in this map, its value is overwritten. If
  /// the number of unique keys is greater than [maximumSize] then the least
  /// recently use keys are evicted. For keys written to by [other], the least
  /// recently user order is determined by [other]'s iteration order.
  @override
  void addAll(Map<K, V> other) => other.forEach((k, v) => this[k] = v);

  @override
  void addEntries(Iterable<MapEntry<K, V>> entries) {
    for (final entry in entries) {
      this[entry.key] = entry.value;
    }
  }

  @override
  Map<K2, V2> cast<K2, V2>() => _entries.cast();

  @override
  void clear() {
    _entries.clear();
    _head = _tail = null;
  }

  @override
  bool containsKey(Object? key) => _entries.containsKey(key);

  @override
  bool containsValue(Object? value) => values.contains(value);

  @override
  Iterable<MapEntry<K, V>> get entries sync* {
    var tail = _tail;
    while (tail != null) {
      yield MapEntry<K, V>(tail.key, tail.value);
      tail = tail.previous;
    }
  }

  /// Applies [action] to each key-value pair of the map in order of MRU to
  /// LRU.
  ///
  /// Calling `action` must not add or remove keys from the map.
  @override
  void forEach(void Function(K key, V value) action) {
    var tail = _tail;
    while (tail != null) {
      action(tail.key, tail.value);
      tail = tail.previous;
    }
  }

  @override
  int get length => _entries.length;

  @override
  bool get isEmpty => _entries.isEmpty;

  @override
  bool get isNotEmpty => _entries.isNotEmpty;

  /// The keys of [this] - in order of MRU to LRU.
  ///
  /// The returned iterable does *not* have efficient `length` or `contains`.
  @override
  Iterable<K> get keys sync* {
    var tail = _tail;
    while (tail != null) {
      yield tail.key;
      tail = tail.previous;
    }
  }

  /// The values of [this] - in order of MRU to LRU.
  ///
  /// The returned iterable does *not* have efficient `length` or `contains`.
  @override
  Iterable<V> get values sync* {
    var tail = _tail;
    while (tail != null) {
      yield tail.value;
      tail = tail.previous;
    }
  }

  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(K key, V value) transform) {
    return _entries.map((k, v) => transform(v.key, v.value));
  }

  @override
  int? get maximumSize => _maximumSize;

  @override
  set maximumSize(int? maximumSize) {
    while (maximumSize != null && length > maximumSize) {
      _removeLru();
    }
    _maximumSize = maximumSize;
  }

  set onLruRemove(LruRemove<V> onLruRemove) {
    _onLruRemove = onLruRemove;
  }

  /// Look up the value associated with [key], or add a new value if it isn't
  /// there. The pair is promoted to the MRU position.
  ///
  /// Otherwise calls [ifAbsent] to get a new value, associates [key] to that
  /// [value], and then returns the new [value], with the key-value pair in the
  /// MRU position. If this causes [length] to exceed [maximumSize], then the
  /// LRU position is removed.
  @override
  V putIfAbsent(K key, V Function() ifAbsent) {
    final entry =
        _entries.putIfAbsent(key, () => _createEntry(key, ifAbsent()));
    if (maximumSize != null && length > maximumSize!) {
      _removeLru();
    }
    _promoteEntry(entry);
    return entry.value;
  }

  /// Get the value for a [key] in the [Map].
  /// The [key] will be promoted to the 'Most Recently Used' position.
  ///
  /// *NOTE*: Calling `[]` inside an iteration over keys/values is currently
  /// unsupported; use [keys] or [values] if you need information about entries
  /// without modifying their position.
  @override
  V? operator [](Object? key) {
    final entry = _entries[key];
    if (entry != null) {
      _promoteEntry(entry);
      return entry.value;
    } else {
      return null;
    }
  }

  /// If [key] already exists, promotes it to the MRU position & assigns
  /// [value].
  ///
  /// Otherwise, adds [key] and [value] to the MRU position.  If [length]
  /// exceeds [maximumSize] while adding, removes the LRU position.
  @override
  void operator []=(K key, V value) {
    // Add this item to the MRU position.
    _insertMru(_createEntry(key, value));

    // Remove the LRU item if the size would be exceeded by adding this item.
    if (maximumSize != null && length > maximumSize!) {
      assert(length == maximumSize! + 1);
      _removeLru();
    }
  }

  @override
  V? remove(Object? key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry == _head && entry == _tail) {
      _head = _tail = null;
    } else if (entry == _head) {
      _head = _head!.next;
      _head?.previous = null;
    } else if (entry == _tail) {
      _tail = _tail!.previous;
      _tail?.next = null;
    } else {
      entry.previous!.next = entry.next;
      entry.next!.previous = entry.previous;
    }
    return entry.value;
  }

  @override
  void removeWhere(bool Function(K key, V value) test) {
    final keysToRemove = <K>[];
    _entries.forEach((key, entry) {
      if (test(key, entry.value)) keysToRemove.add(key);
    });
    keysToRemove.forEach(remove);
  }

  @override
  String toString() => MapBase.mapToString(this);

  @override
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) {
    V newValue;
    if (containsKey(key)) {
      newValue = update(this[key] as V);
    } else {
      if (ifAbsent == null) {
        throw ArgumentError.value(key, 'key', 'Key not in map');
      }
      newValue = ifAbsent();
    }

    // Add this item to the MRU position.
    _insertMru(_createEntry(key, newValue));

    // Remove the LRU item if the size would be exceeded by adding this item.
    if (maximumSize != null && length > maximumSize!) {
      assert(length == maximumSize! + 1);
      _removeLru();
    }
    return newValue;
  }

  @override
  void updateAll(V Function(K key, V value) update) {
    _entries.forEach((key, entry) {
      final newValue = _createEntry(key, update(key, entry.value));
      _entries[key] = newValue;
    });
  }

  /// Moves [entry] to the MRU position, shifting the linked list if necessary.
  void _promoteEntry(_LinkedEntry<K, V> entry) {
    // If this entry is already in the MRU position we are done.
    if (entry == _head) {
      return;
    }

    if (entry.previous != null) {
      // If already existed in the map, link previous to next.
      entry.previous!.next = entry.next;

      // If this was the tail element, assign a new tail.
      if (_tail == entry) {
        _tail = entry.previous;
      }
    }
    // If this entry is not the end of the list then link the next entry to the previous entry.
    if (entry.next != null) {
      entry.next!.previous = entry.previous;
    }

    // Replace head with this element.
    if (_head != null) {
      _head!.previous = entry;
    }
    entry.previous = null;
    entry.next = _head;
    _head = entry;

    // Add a tail if this is the first element.
    if (_tail == null) {
      assert(length == 1);
      _tail = _head;
    }
  }

  /// Creates and returns an entry from [key] and [value].
  _LinkedEntry<K, V> _createEntry(K key, V value) {
    return _LinkedEntry<K, V>(key, value);
  }

  /// If [entry] does not exist, inserts it into the backing map.  If it does,
  /// replaces the existing [_LinkedEntry.value] with [entry.value].  Then, in
  /// either case, promotes [entry] to the MRU position.
  void _insertMru(_LinkedEntry<K, V> entry) {
    // Insert a new entry if necessary (only 1 hash lookup in entire function).
    // Otherwise, just updates the existing value.
    final value = entry.value;
    _promoteEntry(_entries.putIfAbsent(entry.key, () => entry)..value = value);
  }

  /// Removes the LRU position, shifting the linked list if necessary.
  void _removeLru() {
    // Remove the tail from the internal map.
    var entry = _entries.remove(_tail!.key)!;

    // Remove the tail element itself.
    _tail = _tail!.previous;
    _tail?.next = null;

    // If we removed the last element, clear the head too.
    if (_tail == null) {
      _head = null;
    }

    _onLruRemove?.call(entry.value);
  }
}
