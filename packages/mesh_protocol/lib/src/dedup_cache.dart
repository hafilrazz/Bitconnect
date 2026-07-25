import 'dart:collection';
import 'dart:typed_data';

import 'constants.dart';

/// LRU-ish message id deduplication cache.
class DedupCache {
  DedupCache({this.capacity = MeshConstants.defaultDedupCapacity});

  final int capacity;
  final LinkedHashMap<String, int> _map = LinkedHashMap();

  static String keyFor(Uint8List msgId) =>
      msgId.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  bool contains(Uint8List msgId) => _map.containsKey(keyFor(msgId));

  /// Returns true if this is a newly seen id (inserted).
  bool remember(Uint8List msgId) {
    final k = keyFor(msgId);
    if (_map.containsKey(k)) {
      // move to end
      _map.remove(k);
      _map[k] = DateTime.now().millisecondsSinceEpoch;
      return false;
    }
    _map[k] = DateTime.now().millisecondsSinceEpoch;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
    return true;
  }

  int get length => _map.length;

  void clear() => _map.clear();
}
