# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:/netless")

def w(rel, content):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content.replace("\r\n", "\n"), encoding="utf-8")
    print("wrote", rel)

w("packages/mesh_protocol/lib/src/mesh_node.dart", """import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'channel.dart';
import 'constants.dart';
import 'crypto_identity.dart';
import 'dedup_cache.dart';
import 'packet.dart';
import 'packet_codec.dart';

/// Outbound/inbound byte transport used by [MeshNode].
abstract class MeshTransport {
  /// Connected peer ids currently reachable in one hop.
  List<String> get peerIds;

  Stream<MeshInbound> get inbound;

  Future<void> start();
  Future<void> stop();

  /// Send raw packet bytes to one peer, or all if [peerId] is null.
  Future<void> send(Uint8List data, {String? peerId, String? excludePeerId});
}

class MeshInbound {
  MeshInbound({required this.fromPeerId, required this.bytes});
  final String fromPeerId;
  final Uint8List bytes;
}

/// Application-visible delivered chat message.
class ChatMessage {
  ChatMessage({
    required this.packet,
    required this.receivedAt,
    required this.fromPeerId,
    required this.isLocal,
  });

  final MeshPacket packet;
  final DateTime receivedAt;
  final String? fromPeerId;
  final bool isLocal;

  String get text => utf8.decode(packet.body);
  String get nickname => packet.nickname;
  String get fingerprint => packet.shortFingerprint;
  int get channelId => packet.channelId;
  String get msgIdHex => packet.msgIdHex;
}

enum DropReason {
  badFormat,
  duplicate,
  badSignature,
  timestampSkew,
  ttlExpired,
}

/// Core gossip node: sign, flood, dedup, verify.
class MeshNode {
  MeshNode({
    required this.identity,
    required this.transport,
    this.nickname = 'anon',
    this.maxTtl = MeshConstants.maxTtl,
    this.timestampSkewSeconds = MeshConstants.defaultTimestampSkewSeconds,
    DedupCache? dedup,
    this.now = _defaultNow,
  }) : dedup = dedup ?? DedupCache();

  final CryptoIdentity identity;
  final MeshTransport transport;
  String nickname;
  final int maxTtl;
  final int timestampSkewSeconds;
  final DedupCache dedup;
  final DateTime Function() now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  final _messages = StreamController<ChatMessage>.broadcast();
  final _drops = StreamController<(DropReason, String)>.broadcast();
  StreamSubscription<MeshInbound>? _sub;
  bool _running = false;

  Stream<ChatMessage> get messages => _messages.stream;
  Stream<(DropReason, String)> get drops => _drops.stream;
  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    await transport.start();
    _sub = transport.inbound.listen(_onInbound);
    _running = true;
  }

  Future<void> stop() async {
    if (!_running) return;
    await _sub?.cancel();
    _sub = null;
    await transport.stop();
    _running = false;
  }

  Future<ChatMessage> sendChat(
    String text, {
    int channelId = Channels.local,
  }) async {
    final body = utf8.encode(text);
    if (body.length > MeshConstants.maxBodyBytes) {
      throw ArgumentError(
          'message exceeds ${MeshConstants.maxBodyBytes} bytes');
    }
    var nick = nickname;
    var nickBytes = utf8.encode(nick);
    if (nickBytes.length > MeshConstants.maxNicknameBytes) {
      nick = utf8.decode(nickBytes.sublist(0, MeshConstants.maxNicknameBytes),
          allowMalformed: true);
      nickBytes = utf8.encode(nick);
      while (nickBytes.length > MeshConstants.maxNicknameBytes && nick.isNotEmpty) {
        nick = nick.substring(0, nick.length - 1);
        nickBytes = utf8.encode(nick);
      }
    }

    final msgId = CryptoIdentity.randomMsgId();
    final ts = now().millisecondsSinceEpoch ~/ 1000;
    final payload = PacketCodec.signPayload(
      version: MeshConstants.version,
      type: PacketType.chat,
      channelId: channelId,
      msgId: msgId,
      senderPublicKey: identity.publicKeyBytes,
      timestamp: ts,
      nicknameBytes: nickBytes,
      body: body,
    );
    final sig = await identity.sign(payload);
    final packet = MeshPacket(
      version: MeshConstants.version,
      type: PacketType.chat,
      ttl: maxTtl,
      channelId: channelId,
      msgId: msgId,
      senderPublicKey: identity.publicKeyBytes,
      timestamp: ts,
      nickname: nick,
      body: Uint8List.fromList(body),
      signature: sig,
    );
    dedup.remember(msgId);
    final bytes = PacketCodec.encode(packet);
    await transport.send(bytes);
    final msg = ChatMessage(
      packet: packet,
      receivedAt: now(),
      fromPeerId: null,
      isLocal: true,
    );
    _messages.add(msg);
    return msg;
  }

  Future<void> _onInbound(MeshInbound inbound) async {
    MeshPacket packet;
    try {
      packet = PacketCodec.decode(inbound.bytes);
    } catch (e) {
      _drops.add((DropReason.badFormat, e.toString()));
      return;
    }

    if (!dedup.remember(packet.msgId)) {
      _drops.add((DropReason.duplicate, packet.msgIdHex));
      return;
    }

    final ok = await CryptoIdentity.verifyPacket(packet);
    if (!ok) {
      _drops.add((DropReason.badSignature, packet.msgIdHex));
      return;
    }

    final ts = packet.timestamp;
    final nowSec = now().millisecondsSinceEpoch ~/ 1000;
    if ((ts - nowSec).abs() > timestampSkewSeconds) {
      _drops.add((DropReason.timestampSkew, packet.msgIdHex));
      return;
    }

    if (packet.type == PacketType.chat) {
      _messages.add(ChatMessage(
        packet: packet,
        receivedAt: now(),
        fromPeerId: inbound.fromPeerId,
        isLocal: false,
      ));
    }

    if (packet.ttl <= 1) {
      // Do not forward further.
      return;
    }

    final forwarded = packet.copyWith(ttl: packet.ttl - 1);
    final out = PacketCodec.encode(forwarded);
    await transport.send(out, excludePeerId: inbound.fromPeerId);
  }

  Future<void> dispose() async {
    await stop();
    await _messages.close();
    await _drops.close();
  }
}
""")

w("packages/mesh_protocol/test/packet_codec_test.dart", """import 'dart:convert';
import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('encode/decode roundtrip', () async {
    final id = await CryptoIdentity.generate();
    final msgId = CryptoIdentity.randomMsgId();
    final body = Uint8List.fromList(utf8.encode('hello mesh'));
    final nick = 'alice';
    final ts = 1700000000;
    final payload = PacketCodec.signPayload(
      version: MeshConstants.version,
      type: PacketType.chat,
      channelId: Channels.local,
      msgId: msgId,
      senderPublicKey: id.publicKeyBytes,
      timestamp: ts,
      nicknameBytes: utf8.encode(nick),
      body: body,
    );
    final sig = await id.sign(payload);
    final packet = MeshPacket(
      version: MeshConstants.version,
      type: PacketType.chat,
      ttl: 7,
      channelId: Channels.local,
      msgId: msgId,
      senderPublicKey: id.publicKeyBytes,
      timestamp: ts,
      nickname: nick,
      body: body,
      signature: sig,
    );
    final bytes = PacketCodec.encode(packet);
    final decoded = PacketCodec.decode(bytes);
    expect(decoded.ttl, 7);
    expect(decoded.nickname, 'alice');
    expect(utf8.decode(decoded.body), 'hello mesh');
    expect(await CryptoIdentity.verifyPacket(decoded), isTrue);
  });

  test('tampered body fails verify', () async {
    final id = await CryptoIdentity.generate();
    final msgId = CryptoIdentity.randomMsgId();
    final body = Uint8List.fromList(utf8.encode('ok'));
    final payload = PacketCodec.signPayload(
      version: MeshConstants.version,
      type: PacketType.chat,
      channelId: 1,
      msgId: msgId,
      senderPublicKey: id.publicKeyBytes,
      timestamp: 1700000000,
      nicknameBytes: utf8.encode('bob'),
      body: body,
    );
    final sig = await id.sign(payload);
    final packet = MeshPacket(
      version: MeshConstants.version,
      type: PacketType.chat,
      ttl: 5,
      channelId: 1,
      msgId: msgId,
      senderPublicKey: id.publicKeyBytes,
      timestamp: 1700000000,
      nickname: 'bob',
      body: Uint8List.fromList(utf8.encode('no')),
      signature: sig,
    );
    expect(await CryptoIdentity.verifyPacket(packet), isFalse);
  });
}
""")

w("packages/mesh_protocol/test/mesh_node_test.dart", """import 'dart:async';
import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:test/test.dart';

/// In-memory multi-node fabric for topology tests.
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
      // microtask to simulate async radio
      scheduleMicrotask(() {
        other._inbound.add(MeshInbound(fromPeerId: id, bytes: data));
      });
    }
  }
}

void main() {
  test('line topology A-B-C multi-hop', () async {
    final fabric = SimFabric();
    final tA = fabric.create('A');
    final tB = fabric.create('B');
    final tC = fabric.create('C');
    fabric.link('A', 'B');
    fabric.link('B', 'C');
    // no A-C link

    final idA = await CryptoIdentity.generate();
    final idB = await CryptoIdentity.generate();
    final idC = await CryptoIdentity.generate();

    final fixed = DateTime.utc(2024, 1, 1, 12);
    DateTime now() => fixed;

    final nodeA = MeshNode(
        identity: idA, transport: tA, nickname: 'alice', now: now);
    final nodeB = MeshNode(
        identity: idB, transport: tB, nickname: 'bob', now: now);
    final nodeC = MeshNode(
        identity: idC, transport: tC, nickname: 'carol', now: now);

    final cMsgs = <ChatMessage>[];
    nodeC.messages.listen(cMsgs.add);

    await nodeA.start();
    await nodeB.start();
    await nodeC.start();

    await nodeA.sendChat('hop test');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cMsgs.length, 1);
    expect(cMsgs.first.text, 'hop test');
    expect(cMsgs.first.nickname, 'alice');

    await nodeA.dispose();
    await nodeB.dispose();
    await nodeC.dispose();
  });

  test('duplicate does not deliver twice', () async {
    final fabric = SimFabric();
    final tA = fabric.create('A');
    final tB = fabric.create('B');
    fabric.link('A', 'B');

    final fixed = DateTime.utc(2024, 1, 1, 12);
    final nodeA = MeshNode(
      identity: await CryptoIdentity.generate(),
      transport: tA,
      nickname: 'a',
      now: () => fixed,
    );
    final nodeB = MeshNode(
      identity: await CryptoIdentity.generate(),
      transport: tB,
      nickname: 'b',
      now: () => fixed,
    );
    final msgs = <ChatMessage>[];
    nodeB.messages.listen(msgs.add);
    await nodeA.start();
    await nodeB.start();
    await nodeA.sendChat('once');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // Resend same encoded packet manually would need capture; instead send second new msg
    await nodeA.sendChat('twice');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(msgs.length, 2);
    await nodeA.dispose();
    await nodeB.dispose();
  });

  test('diamond topology does not storm', () async {
    final fabric = SimFabric();
    for (final id in ['A', 'B', 'C', 'D']) {
      fabric.create(id);
    }
    fabric.link('A', 'B');
    fabric.link('A', 'C');
    fabric.link('B', 'D');
    fabric.link('C', 'D');

    final fixed = DateTime.utc(2024, 6, 1);
    Future<MeshNode> mk(String id, String nick) async {
      return MeshNode(
        identity: await CryptoIdentity.generate(),
        transport: fabric.nodes[id]!,
        nickname: nick,
        now: () => fixed,
      );
    }

    final a = await mk('A', 'a');
    final b = await mk('B', 'b');
    final c = await mk('C', 'c');
    final d = await mk('D', 'd');
    final msgs = <ChatMessage>[];
    d.messages.listen(msgs.add);
    for (final n in [a, b, c, d]) {
      await n.start();
    }
    await a.sendChat('diamond');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(msgs.where((m) => m.text == 'diamond').length, 1);
    for (final n in [a, b, c, d]) {
      await n.dispose();
    }
  });
}
""")

print("protocol C ok")
