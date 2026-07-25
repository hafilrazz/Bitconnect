import 'dart:async';
import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';

/// Multi-node in-process fabric for demos and tests.
class SimFabric {
  final Map<String, SimTransport> nodes = {};
  final Map<String, Set<String>> links = {};

  SimTransport create(String id) {
    final t = SimTransport(id, this);
    nodes[id] = t;
    links.putIfAbsent(id, () => {});
    return t;
  }

  void link(String a, String b) {
    links.putIfAbsent(a, () => {}).add(b);
    links.putIfAbsent(b, () => {}).add(a);
  }

  void unlink(String a, String b) {
    links[a]?.remove(b);
    links[b]?.remove(a);
  }
}

class SimTransport implements MeshTransport {
  SimTransport(this.id, this.fabric);

  final String id;
  final SimFabric fabric;
  final _inbound = StreamController<MeshInbound>.broadcast();
  bool _up = false;

  @override
  List<String> get peerIds =>
      _up ? (fabric.links[id]?.toList() ?? []) : <String>[];

  @override
  Stream<MeshInbound> get inbound => _inbound.stream;

  @override
  Future<void> start() async => _up = true;

  @override
  Future<void> stop() async => _up = false;

  @override
  Future<void> send(Uint8List data,
      {String? peerId, String? excludePeerId}) async {
    if (!_up) return;
    final targets = <String>[];
    if (peerId != null) {
      if (fabric.links[id]?.contains(peerId) == true) targets.add(peerId);
    } else {
      for (final p in fabric.links[id] ?? <String>{}) {
        if (p != excludePeerId) targets.add(p);
      }
    }
    for (final t in targets) {
      final other = fabric.nodes[t];
      if (other == null || !other._up) continue;
      scheduleMicrotask(() {
        other._inbound.add(MeshInbound(fromPeerId: id, bytes: data));
      });
    }
  }
}
