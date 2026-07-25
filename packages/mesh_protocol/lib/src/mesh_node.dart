import 'dart:async';
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
