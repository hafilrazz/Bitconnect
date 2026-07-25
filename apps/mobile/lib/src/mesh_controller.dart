import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mesh_ble/mesh_ble.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:mesh_transport/mesh_transport.dart';

enum TransportMode { fake, ble }

/// Owns MeshNode lifecycle and message list for the UI.
class MeshController extends ChangeNotifier {
  MeshController({
    required this.identity,
    required this.nickname,
    this.mode = TransportMode.fake,
  });

  final CryptoIdentity identity;
  String nickname;
  TransportMode mode;

  MeshNode? _node;
  MeshTransport? _transport;
  final List<ChatMessage> messages = [];
  StreamSubscription<ChatMessage>? _msgSub;
  bool meshOn = false;
  String? lastError;
  int peerCount = 0;
  Timer? _peerTimer;

  // Simulated multi-node for in-app demo (fake mode only)
  SimFabric? _sim;
  final List<MeshNode> _simRelays = [];

  Future<void> startMesh() async {
    lastError = null;
    try {
      await stopMesh();
      if (mode == TransportMode.ble) {
        final ok = await ensureBlePermissions();
        if (!ok) {
          throw StateError('Bluetooth permissions not granted');
        }
        _transport = BleMeshTransport();
      } else {
        _sim = SimFabric();
        final local = _sim!.create('local');
        // Relay path: local -- r1 -- r2 (for multi-hop demo inject)
        final r1 = _sim!.create('relay1');
        final r2 = _sim!.create('relay2');
        _sim!.link('local', 'relay1');
        _sim!.link('relay1', 'relay2');
        _transport = local;

        // Silent relay nodes so hop demos work when injecting at r2 later
        final id1 = await CryptoIdentity.generate();
        final id2 = await CryptoIdentity.generate();
        final n1 = MeshNode(identity: id1, transport: r1, nickname: 'relay1');
        final n2 = MeshNode(identity: id2, transport: r2, nickname: 'relay2');
        await n1.start();
        await n2.start();
        _simRelays.addAll([n1, n2]);
      }

      _node = MeshNode(
        identity: identity,
        transport: _transport!,
        nickname: nickname,
      );
      _msgSub = _node!.messages.listen((m) {
        messages.add(m);
        notifyListeners();
      });
      await _node!.start();
      meshOn = true;
      _peerTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final n = _transport?.peerIds.length ?? 0;
        if (n != peerCount) {
          peerCount = n;
          notifyListeners();
        }
      });
      peerCount = _transport?.peerIds.length ?? 0;
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      meshOn = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopMesh() async {
    _peerTimer?.cancel();
    _peerTimer = null;
    await _msgSub?.cancel();
    _msgSub = null;
    await _node?.dispose();
    _node = null;
    for (final r in _simRelays) {
      await r.dispose();
    }
    _simRelays.clear();
    _sim = null;
    if (_transport is FakeTransport) {
      await (_transport as FakeTransport).dispose();
    } else {
      await _transport?.stop();
    }
    _transport = null;
    meshOn = false;
    peerCount = 0;
    notifyListeners();
  }

  Future<void> send(String text) async {
    final node = _node;
    if (node == null || !meshOn) {
      throw StateError('Mesh is off');
    }
    node.nickname = nickname;
    await node.sendChat(text);
  }

  /// Inject a remote chat via sim leaf -> relay2 -> relay1 -> local (multi-hop).
  Future<void> injectSimulatedRemote(String text, {String nick = 'remote'}) async {
    if (mode != TransportMode.fake || _sim == null) return;
    final id = await CryptoIdentity.generate();
    final leaf =
        _sim!.create("leaf-${DateTime.now().microsecondsSinceEpoch}");
    _sim!.link(leaf.id, 'relay2');
    final sender = MeshNode(identity: id, transport: leaf, nickname: nick);
    await sender.start();
    await sender.sendChat(text);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sender.dispose();
  }

  @override
  void dispose() {
    unawaited(stopMesh());
    super.dispose();
  }
}
