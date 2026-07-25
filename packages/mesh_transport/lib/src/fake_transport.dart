import 'dart:async';
import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';

/// Loopback transport: messages sent come back from a virtual peer.
/// Useful for single-device UI demos without BLE.
class FakeTransport implements MeshTransport {
  FakeTransport({this.loopbackPeerId = 'loopback', this.echo = false});

  final String loopbackPeerId;
  /// If true, sends are echoed back as inbound (for local UI testing).
  final bool echo;

  final _inbound = StreamController<MeshInbound>.broadcast();
  final _peers = <String>{};
  bool _up = false;

  void addVirtualPeer(String id) => _peers.add(id);
  void removeVirtualPeer(String id) => _peers.remove(id);

  @override
  List<String> get peerIds => _up ? _peers.toList() : <String>[];

  @override
  Stream<MeshInbound> get inbound => _inbound.stream;

  @override
  Future<void> start() async {
    _up = true;
    if (_peers.isEmpty) {
      _peers.add(loopbackPeerId);
    }
  }

  @override
  Future<void> stop() async {
    _up = false;
  }

  @override
  Future<void> send(Uint8List data,
      {String? peerId, String? excludePeerId}) async {
    if (!_up) return;
    if (echo) {
      scheduleMicrotask(() {
        _inbound.add(MeshInbound(fromPeerId: loopbackPeerId, bytes: data));
      });
    }
  }

  /// Inject a packet as if received from [fromPeerId].
  void inject(Uint8List bytes, {String fromPeerId = 'remote'}) {
    if (!_up) return;
    _inbound.add(MeshInbound(fromPeerId: fromPeerId, bytes: bytes));
  }

  Future<void> dispose() async {
    await stop();
    await _inbound.close();
  }
}
