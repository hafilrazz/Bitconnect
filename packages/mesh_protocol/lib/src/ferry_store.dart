import 'constants.dart';
import 'packet.dart';

/// Store-and-forward ferry: hold packets until target peer is seen again.
class FerryStore {
  FerryStore({
    this.maxQueue = MeshConstants.ferryMaxQueue,
    this.maxAgeSeconds = MeshConstants.ferryMaxAgeSeconds,
  });

  final int maxQueue;
  final int maxAgeSeconds;
  final List<_FerryItem> _items = [];

  int get length => _items.length;

  void enqueue(MeshPacket packet, {String? targetPeerHint}) {
    _purge();
    if (_items.length >= maxQueue) {
      _items.removeAt(0);
    }
    _items.add(_FerryItem(
      packet: packet,
      storedAt: DateTime.now().toUtc(),
      targetPeerHint: targetPeerHint,
    ));
  }

  /// Drain packets that should be rebroadcast (optionally filter by peer).
  List<MeshPacket> drainForRelay({String? peerId}) {
    _purge();
    if (_items.isEmpty) return const [];
    final out = <MeshPacket>[];
    final keep = <_FerryItem>[];
    for (final it in _items) {
      if (peerId != null &&
          it.targetPeerHint != null &&
          it.targetPeerHint != peerId) {
        keep.add(it);
        continue;
      }
      out.add(it.packet);
    }
    // After successful drain we drop delivered-ish items when no specific target
    if (peerId == null) {
      _items.clear();
    } else {
      _items
        ..clear()
        ..addAll(keep);
    }
    return out;
  }

  /// Peek without clearing (for UI).
  List<MeshPacket> peek() {
    _purge();
    return _items.map((e) => e.packet).toList();
  }

  void _purge() {
    final now = DateTime.now().toUtc();
    _items.removeWhere(
      (it) => now.difference(it.storedAt).inSeconds > maxAgeSeconds,
    );
  }

  void clear() => _items.clear();
}

class _FerryItem {
  _FerryItem({
    required this.packet,
    required this.storedAt,
    this.targetPeerHint,
  });
  final MeshPacket packet;
  final DateTime storedAt;
  final String? targetPeerHint;
}
