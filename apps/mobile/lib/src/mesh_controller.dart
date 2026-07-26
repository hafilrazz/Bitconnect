import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mesh_ble/mesh_ble.dart';
import 'package:mesh_internet/mesh_internet.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:mesh_transport/mesh_transport.dart';

import 'identity_store.dart';

enum TransportMode { fake, ble }

/// Owns mesh + internet E2E lifecycle for the UI.
class MeshController extends ChangeNotifier {
  MeshController({
    required this.appIdentity,
  }) : nickname = appIdentity.nickname;

  final AppIdentity appIdentity;
  CryptoIdentity get identity => appIdentity.sign;
  String nickname;

  TransportMode mode =
      (!kIsWeb && Platform.isAndroid) ? TransportMode.ble : TransportMode.fake;

  MeshNode? _node;
  MeshTransport? _transport;
  final List<ChatMessage> messages = [];
  StreamSubscription<ChatMessage>? _msgSub;
  bool meshOn = false;
  String? lastError;
  int peerCount = 0;
  Timer? _peerTimer;

  SimFabric? _sim;
  final List<MeshNode> _simRelays = [];

  // Internet E2E
  InternetE2eService? _internet;
  StreamSubscription<InternetDm>? _inetSub;
  StreamSubscription<String>? _inetStatusSub;
  bool internetOn = false;
  String? internetStatus;
  final List<InternetDm> internetMessages = [];
  String? activePeerId;
  List<Contact> contacts = [];

  String get netlessId => appIdentity.netlessId;

  Future<void> startMesh() async {
    lastError = null;
    try {
      await stopMesh();
      if (mode == TransportMode.ble) {
        final ok = await ensureBlePermissions();
        if (!ok) {
          throw StateError('Bluetooth permissions not granted');
        }
        if (!kIsWeb && Platform.isAndroid) {
          _transport = AndroidBleMeshTransport();
        } else {
          _transport = BleMeshTransport();
        }
      } else {
        _sim = SimFabric();
        final local = _sim!.create('local');
        final r1 = _sim!.create('relay1');
        final r2 = _sim!.create('relay2');
        _sim!.link('local', 'relay1');
        _sim!.link('relay1', 'relay2');
        _transport = local;

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

  Future<void> injectSimulatedRemote(String text,
      {String nick = 'remote'}) async {
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

  // --- Internet E2E ---

  Future<void> startInternet() async {
    lastError = null;
    try {
      await stopInternet();
      _internet = InternetE2eService(
        signIdentity: appIdentity.sign,
        encIdentity: appIdentity.enc,
        nickname: nickname,
        keySeed: appIdentity.encSeed,
      );
      _inetSub = _internet!.messages.listen((dm) {
        internetMessages.add(dm);
        // auto-select peer on first inbound
        if (!dm.isLocal && activePeerId == null) {
          activePeerId = dm.peerNetlessId;
        }
        notifyListeners();
      });
      _inetStatusSub = _internet!.status.listen((s) {
        internetStatus = s;
        notifyListeners();
      });
      await _internet!.start();
      internetOn = true;
      internetStatus = 'E2E online · id ${netlessId.substring(0, 12)}…';
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      internetOn = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopInternet() async {
    await _inetSub?.cancel();
    _inetSub = null;
    await _inetStatusSub?.cancel();
    _inetStatusSub = null;
    await _internet?.dispose();
    _internet = null;
    internetOn = false;
    notifyListeners();
  }

  Future<void> sendInternetDm(String text) async {
    final peer = activePeerId;
    final inet = _internet;
    if (inet == null || !internetOn) {
      throw StateError('Internet E2E is off');
    }
    if (peer == null || peer.isEmpty) {
      throw StateError('Pick a contact (recipient Bitconnect ID)');
    }
    inet.nickname = nickname;
    await inet.sendDm(recipientNetlessId: peer, text: text);
  }

  void setActivePeer(String netlessId) {
    activePeerId = netlessId.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    notifyListeners();
  }

  Future<void> addContact(Contact c) async {
    final id = c.netlessId.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (id.length != 64) {
      throw ArgumentError('Bitconnect ID must be 64 hex chars (X25519 pubkey)');
    }
    contacts.removeWhere((x) => x.netlessId == id);
    contacts = [...contacts, Contact(name: c.name, netlessId: id)];
    activePeerId = id;
    notifyListeners();
  }

  List<InternetDm> messagesForActivePeer() {
    final peer = activePeerId;
    if (peer == null) return const [];
    return internetMessages
        .where((m) => m.peerNetlessId == peer || (m.isLocal && m.peerNetlessId == peer))
        .toList();
  }

  @override
  void dispose() {
    unawaited(stopMesh());
    unawaited(stopInternet());
    super.dispose();
  }
}
