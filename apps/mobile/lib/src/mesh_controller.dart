import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mesh_ble/mesh_ble.dart';
import 'package:mesh_internet/mesh_internet.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:mesh_transport/mesh_transport.dart';

import 'identity_store.dart';
import 'image_codec_util.dart';

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

  PowerMode powerMode = PowerMode.balanced;

  MeshNode? _node;
  MeshTransport? _transport;
  final List<ChatMessage> messages = [];
  /// msgIdHex -> status for local sends
  final Map<String, DeliveryStatus> delivery = {};
  /// mediaId -> image bytes for UI
  final Map<String, Uint8List> mediaGallery = {};
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<AckEvent>? _ackSub;
  bool meshOn = false;
  String? lastError;
  int peerCount = 0;
  Timer? _peerTimer;

  SimFabric? _sim;
  final List<MeshNode> _simRelays = [];

  // Channels
  final List<String> channelNames = ['#local', '#general', '#alerts'];
  String activeChannelName = '#local';
  int get activeChannelId => Channels.idForName(activeChannelName);
  /// channelId -> key b64 for encrypted local channels / groups
  final Map<int, String> channelKeyB64 = {};

  // Internet E2E
  InternetE2eService? _internet;
  StreamSubscription<InternetDm>? _inetSub;
  StreamSubscription<String>? _inetStatusSub;
  bool internetOn = false;
  String? internetStatus;
  final List<InternetDm> internetMessages = [];
  String? activePeerId;
  List<Contact> contacts = [];

  // Groups (internet-style shared key groups for local mesh too)
  final List<GroupInfo> groups = [];

  String get netlessId => appIdentity.netlessId;
  int get ferryQueued => _node?.ferry.length ?? 0;

  List<ChatMessage> get messagesForActiveChannel =>
      messages.where((m) => m.channelId == activeChannelId).toList();

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
        powerMode: powerMode,
      );
      _applyChannelKeys();
      _msgSub = _node!.messages.listen(_onMeshMessage);
      _ackSub = _node!.acks.listen((a) {
        final st = a.type == PacketType.read
            ? DeliveryStatus.read
            : DeliveryStatus.delivered;
        final prev = delivery[a.refMsgIdHex];
        if (prev == null ||
            prev.index < st.index ||
            (prev == DeliveryStatus.sent && st == DeliveryStatus.delivered)) {
          delivery[a.refMsgIdHex] = st;
          for (final m in messages) {
            if (m.isLocal && m.msgIdHex == a.refMsgIdHex) {
              m.status = st;
            }
          }
          notifyListeners();
        }
      });
      await _node!.start();
      meshOn = true;
      _peerTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final n = _transport?.peerIds.length ?? 0;
        if (n != peerCount) {
          peerCount = n;
          notifyListeners();
        }
        // When peers appear, flush ferry
        if (n > 0) {
          unawaited(_node?.flushFerry() ?? Future.value());
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

  void _applyChannelKeys() {
    final node = _node;
    if (node == null) return;
    for (final e in channelKeyB64.entries) {
      try {
        node.setChannelKey(e.key, GroupCrypto.decodeKeyB64(e.value));
      } catch (_) {}
    }
  }

  Future<void> stopMesh() async {
    _peerTimer?.cancel();
    _peerTimer = null;
    await _msgSub?.cancel();
    _msgSub = null;
    await _ackSub?.cancel();
    _ackSub = null;
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
    final encrypt = channelKeyB64.containsKey(activeChannelId);
    final msg = await node.sendChat(
      text,
      channelId: activeChannelId,
      encrypt: encrypt,
      requestAck: true,
    );
    delivery[msg.msgIdHex] = DeliveryStatus.sent;
    notifyListeners();
  }

  void _onMeshMessage(ChatMessage m) {
    // Images / files: always one bubble with full bytes when present
    if (m.mediaBytes != null && m.mediaBytes!.isNotEmpty) {
      final id = m.mediaId ?? m.msgIdHex;
      mediaGallery[id] = m.mediaBytes!;
      m.mediaId = id;
      m.isMedia = true;
      // Dedupe by mediaId
      final idx = messages.indexWhere((x) => x.mediaId == id);
      if (idx >= 0) {
        messages[idx].mediaBytes = m.mediaBytes;
        messages[idx].plainText = m.plainText;
        notifyListeners();
        return;
      }
      messages.add(m);
      notifyListeners();
      return;
    }

    messages.add(m);
    notifyListeners();
  }

  /// Compress + binary multi-fragment send. One local bubble with the photo.
  Future<void> sendImageBytes(Uint8List bytes,
      {String filename = 'photo.jpg'}) async {
    final node = _node;
    if (node == null || !meshOn) throw StateError('Mesh is off');

    final data = compressForMesh(bytes);
    final safeName = filename.toLowerCase().endsWith('.jpg') ||
            filename.toLowerCase().endsWith('.jpeg')
        ? filename
        : 'photo.jpg';

    final file = FilePacket(
      fileName: safeName,
      mimeType: 'image/jpeg',
      content: data,
    );

    final msg = await node.sendFile(
      file: file,
      channelId: activeChannelId,
      emitToUi: true,
    );
    final id = msg.mediaId ?? msg.msgIdHex;
    mediaGallery[id] = data;
    msg.mediaBytes = data;
    msg.mediaId = id;
    msg.isMedia = true;
    // Ensure it is in the list once
    messages.removeWhere((m) => m.mediaId == id);
    messages.add(msg);
    delivery[msg.msgIdHex] = DeliveryStatus.sent;
    notifyListeners();
  }

  Future<void> markRead(ChatMessage m) async {
    final node = _node;
    if (node == null || !meshOn || m.isLocal) return;
    await node.sendReceipt(
      type: PacketType.read,
      refMsgId: m.packet.msgId,
      channelId: m.channelId,
    );
  }

  void setActiveChannel(String name) {
    activeChannelName = Channels.normalizeName(name);
    if (!channelNames.contains(activeChannelName)) {
      channelNames.add(activeChannelName);
    }
    notifyListeners();
  }

  void addChannel(String name) {
    final n = Channels.normalizeName(name);
    if (!channelNames.contains(n)) channelNames.add(n);
    activeChannelName = n;
    notifyListeners();
  }

  /// Create encrypted group/channel key and set as active channel.
  String createEncryptedChannel(String name) {
    final n = Channels.normalizeName(name);
    final id = Channels.idForName(n);
    final key = GroupCrypto.randomKey();
    final b64 = GroupCrypto.encodeKeyB64(key);
    channelKeyB64[id] = b64;
    if (!channelNames.contains(n)) channelNames.add(n);
    activeChannelName = n;
    _node?.setChannelKey(id, key);
    groups.add(GroupInfo(name: n, channelId: id, keyB64: b64));
    notifyListeners();
    return b64;
  }

  void joinEncryptedChannel(String name, String keyB64) {
    final n = Channels.normalizeName(name);
    final id = Channels.idForName(n);
    final key = GroupCrypto.decodeKeyB64(keyB64);
    channelKeyB64[id] = GroupCrypto.encodeKeyB64(key);
    if (!channelNames.contains(n)) channelNames.add(n);
    activeChannelName = n;
    _node?.setChannelKey(id, key);
    groups.removeWhere((g) => g.channelId == id);
    groups.add(GroupInfo(name: n, channelId: id, keyB64: channelKeyB64[id]!));
    notifyListeners();
  }

  void setPowerMode(PowerMode mode) {
    powerMode = mode;
    if (_node != null) {
      _node!.powerMode = mode;
    }
    notifyListeners();
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
    await sender.sendChat(text, channelId: activeChannelId);
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

  Future<void> sendInternetMedia(Uint8List bytes, {String name = 'photo.jpg'}) async {
    // Base64 embed in E2E text payload (size-capped)
    if (bytes.length > 40 * 1024) {
      throw StateError('Image too large (max ~40KB for E2E demo)');
    }
    final b64 = base64Encode(bytes);
    await sendInternetDm('MEDIA:image/jpeg:$name:$b64');
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
        .where((m) =>
            m.peerNetlessId == peer || (m.isLocal && m.peerNetlessId == peer))
        .toList();
  }

  @override
  void dispose() {
    unawaited(stopMesh());
    unawaited(stopInternet());
    super.dispose();
  }
}

class GroupInfo {
  GroupInfo({
    required this.name,
    required this.channelId,
    required this.keyB64,
  });
  final String name;
  final int channelId;
  final String keyB64;
}
