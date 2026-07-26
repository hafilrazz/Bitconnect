import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'channel.dart';
import 'constants.dart';
import 'crypto_identity.dart';
import 'dedup_cache.dart';
import 'ferry_store.dart';
import 'file_packet.dart';
import 'group_crypto.dart';
import 'media_chunk.dart';
import 'packet.dart';
import 'packet_codec.dart';
import 'rate_limiter.dart';

/// Outbound/inbound byte transport used by [MeshNode].
abstract class MeshTransport {
  List<String> get peerIds;
  Stream<MeshInbound> get inbound;
  Future<void> start();
  Future<void> stop();
  Future<void> send(Uint8List data, {String? peerId, String? excludePeerId});
}

class MeshInbound {
  MeshInbound({required this.fromPeerId, required this.bytes});
  final String fromPeerId;
  final Uint8List bytes;
}

enum DeliveryStatus { sending, sent, delivered, read, failed }

/// Application-visible delivered chat message.
class ChatMessage {
  ChatMessage({
    required this.packet,
    required this.receivedAt,
    required this.fromPeerId,
    required this.isLocal,
    this.status = DeliveryStatus.sent,
    this.plainText,
    this.isMedia = false,
    this.mediaBytes,
    this.mediaId,
  });

  final MeshPacket packet;
  final DateTime receivedAt;
  final String? fromPeerId;
  final bool isLocal;
  DeliveryStatus status;
  /// Decrypted / decoded body for UI (when channel encrypted or media).
  String? plainText;
  bool isMedia;
  /// Reassembled image/file bytes (when available).
  Uint8List? mediaBytes;
  String? mediaId;

  String get text => plainText ?? utf8.decode(packet.body, allowMalformed: true);
  String get nickname => packet.nickname;
  String get fingerprint => packet.shortFingerprint;
  int get channelId => packet.channelId;
  String get msgIdHex => packet.msgIdHex;
}

class AckEvent {
  AckEvent({
    required this.type,
    required this.refMsgIdHex,
    required this.fromFingerprint,
    required this.channelId,
  });
  final PacketType type; // ack or read
  final String refMsgIdHex;
  final String fromFingerprint;
  final int channelId;
}

enum DropReason {
  badFormat,
  duplicate,
  badSignature,
  timestampSkew,
  ttlExpired,
  rateLimited,
  decryptFailed,
}

/// Core gossip node: sign, flood, dedup, verify, ACK/read, ferry, rate limit.
class MeshNode {
  MeshNode({
    required this.identity,
    required this.transport,
    this.nickname = 'anon',
    this.maxTtl = MeshConstants.maxTtl,
    this.timestampSkewSeconds = MeshConstants.defaultTimestampSkewSeconds,
    DedupCache? dedup,
    RateLimiter? rateLimiter,
    FerryStore? ferry,
    this.now = _defaultNow,
    this.powerMode = PowerMode.balanced,
  })  : dedup = dedup ?? DedupCache(),
        rateLimiter = rateLimiter ??
            RateLimiter(
              maxEvents: MeshConstants.rateLimitMaxPackets,
              window: Duration(milliseconds: MeshConstants.rateLimitWindowMs),
            ),
        ferry = ferry ?? FerryStore();

  final CryptoIdentity identity;
  final MeshTransport transport;
  String nickname;
  final int maxTtl;
  final int timestampSkewSeconds;
  final DedupCache dedup;
  final RateLimiter rateLimiter;
  final FerryStore ferry;
  final DateTime Function() now;
  PowerMode powerMode;

  /// channelId -> optional 32-byte group/channel key
  final Map<int, Uint8List> channelKeys = {};
  final FileAssembler _fileAssembler = FileAssembler();

  static DateTime _defaultNow() => DateTime.now().toUtc();

  final _messages = StreamController<ChatMessage>.broadcast();
  final _acks = StreamController<AckEvent>.broadcast();
  final _drops = StreamController<(DropReason, String)>.broadcast();
  StreamSubscription<MeshInbound>? _sub;
  Timer? _ferryTimer;
  bool _running = false;

  Stream<ChatMessage> get messages => _messages.stream;
  Stream<AckEvent> get acks => _acks.stream;
  Stream<(DropReason, String)> get drops => _drops.stream;
  bool get isRunning => _running;

  void setChannelKey(int channelId, Uint8List? key32) {
    if (key32 == null) {
      channelKeys.remove(channelId);
    } else {
      channelKeys[channelId] = key32;
    }
  }

  Future<void> start() async {
    if (_running) return;
    await transport.start();
    _sub = transport.inbound.listen(_onInbound);
    _ferryTimer = Timer.periodic(_ferryInterval(), (_) => flushFerry());
    _running = true;
  }

  Duration _ferryInterval() {
    switch (powerMode) {
      case PowerMode.performance:
        return const Duration(seconds: 8);
      case PowerMode.balanced:
        return const Duration(seconds: 20);
      case PowerMode.saver:
        return const Duration(seconds: 60);
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _ferryTimer?.cancel();
    _ferryTimer = null;
    await _sub?.cancel();
    _sub = null;
    await transport.stop();
    _running = false;
  }

  Future<void> flushFerry() async {
    if (!_running) return;
    final batch = ferry.drainForRelay();
    for (final p in batch) {
      if (p.ttl <= 1) continue;
      final forwarded = p.copyWith(ttl: p.ttl - 1);
      try {
        await transport.send(PacketCodec.encode(forwarded));
      } catch (_) {}
    }
  }

  Future<ChatMessage> sendChat(
    String text, {
    int channelId = Channels.local,
    bool requestAck = true,
    bool encrypt = false,
  }) async {
    var body = utf8.encode(text);
    var flags = requestAck ? MeshConstants.flagNeedsAck : 0;

    if (encrypt || channelKeys.containsKey(channelId)) {
      final key = channelKeys[channelId];
      if (key == null) {
        throw StateError('no channel key for encrypted send');
      }
      body = await GroupCrypto.encrypt(key32: key, plaintext: body);
      flags |= MeshConstants.flagEncrypted;
    }

    return _sendPacket(
      type: PacketType.chat,
      channelId: channelId,
      body: Uint8List.fromList(body),
      flags: flags,
      plainText: text,
      isMedia: false,
    );
  }

  Future<ChatMessage> sendMedia({
    required MediaEnvelope media,
    int channelId = Channels.local,
    bool encrypt = false,
  }) async {
    var body = utf8.encode(media.encode());
    var flags = MeshConstants.flagMedia | MeshConstants.flagNeedsAck;
    if (encrypt || channelKeys.containsKey(channelId)) {
      final key = channelKeys[channelId];
      if (key == null) throw StateError('no channel key for encrypted media');
      body = await GroupCrypto.encrypt(key32: key, plaintext: body);
      flags |= MeshConstants.flagEncrypted;
    }
    if (body.length > MeshConstants.maxBodyBytes) {
      throw ArgumentError(
          'media exceeds ${MeshConstants.maxBodyBytes} bytes after encode');
    }
    return _sendPacket(
      type: PacketType.chat,
      channelId: channelId,
      body: Uint8List.fromList(body),
      flags: flags,
      plainText: media.caption.isEmpty ? '📎 ${media.filename}' : media.caption,
      isMedia: true,
    );
  }

  Future<ChatMessage> _sendPacket({
    required PacketType type,
    required int channelId,
    required Uint8List body,
    required int flags,
    String? plainText,
    bool isMedia = false,
    bool skipRateLimit = false,
    Uint8List? mediaBytes,
    String? mediaId,
    bool emitToUi = true,
    bool enqueueFerry = true,
  }) async {
    if (!skipRateLimit && !rateLimiter.allow(now())) {
      throw StateError('rate limited — slow down to protect the mesh');
    }
    if (body.length > MeshConstants.maxBodyBytes) {
      throw ArgumentError(
          'message exceeds ${MeshConstants.maxBodyBytes} bytes');
    }
    var nick = nickname;
    var nickBytes = utf8.encode(nick);
    while (nickBytes.length > MeshConstants.maxNicknameBytes &&
        nick.isNotEmpty) {
      nick = nick.substring(0, nick.length - 1);
      nickBytes = utf8.encode(nick);
    }

    final msgId = CryptoIdentity.randomMsgId();
    final ts = now().millisecondsSinceEpoch ~/ 1000;
    final payload = PacketCodec.signPayload(
      version: MeshConstants.version,
      type: type,
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
      type: type,
      ttl: maxTtl,
      flags: flags,
      channelId: channelId,
      msgId: msgId,
      senderPublicKey: identity.publicKeyBytes,
      timestamp: ts,
      nickname: nick,
      body: body,
      signature: sig,
    );
    dedup.remember(msgId);
    await transport.send(PacketCodec.encode(packet));
    // Ferry text chats only — media chunks must not be re-flooded.
    if (enqueueFerry &&
        type == PacketType.chat &&
        (flags & MeshConstants.flagMedia) == 0) {
      ferry.enqueue(packet);
    }

    final msg = ChatMessage(
      packet: packet,
      receivedAt: now(),
      fromPeerId: null,
      isLocal: true,
      status: DeliveryStatus.sent,
      plainText: plainText,
      isMedia: isMedia,
      mediaBytes: mediaBytes,
      mediaId: mediaId,
    );
    if (emitToUi) {
      _messages.add(msg);
    }
    return msg;
  }

  /// Send image/file as binary [FilePacket] split into [FileFragment]s.
  /// UI gets **one** message with full image bytes after all fragments are written.
  Future<ChatMessage> sendFile({
    required FilePacket file,
    int channelId = Channels.local,
    bool emitToUi = true,
  }) async {
    if (file.content.length > FilePacket.maxPayloadBytes) {
      throw ArgumentError('file too large: ${file.content.length}');
    }
    final encoded = file.encode();
    // 8-byte transfer id
    final fullId = CryptoIdentity.randomMsgId();
    final transferId = Uint8List.fromList(fullId.sublist(0, FileFragment.idLen));
    final frags = FileFragment.split(transferId, encoded);
    final transferHex = FileFragment.idHex(transferId);
    final label = '📎 ${file.fileName ?? 'file'}';

    ChatMessage? last;
    for (var i = 0; i < frags.length; i++) {
      final body = frags[i].encode();
      if (body.length > MeshConstants.maxBodyBytes) {
        throw StateError('fragment too large: ${body.length}');
      }
      last = await _sendPacket(
        type: PacketType.file,
        channelId: channelId,
        body: body,
        flags: 0,
        plainText: label,
        isMedia: true,
        skipRateLimit: true,
        mediaBytes: file.content,
        mediaId: transferHex,
        emitToUi: false,
        enqueueFerry: false,
      );
      // Give BLE stack time — critical for multi-fragment delivery
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    final out = last!;
    out.mediaBytes = Uint8List.fromList(file.content);
    out.mediaId = transferHex;
    out.isMedia = true;
    out.plainText = label;
    out.status = DeliveryStatus.sent;
    if (emitToUi) _messages.add(out);
    return out;
  }

  /// Send ACK or READ referencing [refMsgId].
  Future<void> sendReceipt({
    required PacketType type,
    required Uint8List refMsgId,
    required int channelId,
  }) async {
    if (type != PacketType.ack && type != PacketType.read) {
      throw ArgumentError('type must be ack or read');
    }
    final body = refMsgId; // 16-byte ref
    final nickBytes = utf8.encode(nickname);
    final msgId = CryptoIdentity.randomMsgId();
    final ts = now().millisecondsSinceEpoch ~/ 1000;
    final payload = PacketCodec.signPayload(
      version: MeshConstants.version,
      type: type,
      channelId: channelId,
      msgId: msgId,
      senderPublicKey: identity.publicKeyBytes,
      timestamp: ts,
      nicknameBytes: nickBytes.length > MeshConstants.maxNicknameBytes
          ? nickBytes.sublist(0, MeshConstants.maxNicknameBytes)
          : nickBytes,
      body: body,
    );
    final sig = await identity.sign(payload);
    final packet = MeshPacket(
      version: MeshConstants.version,
      type: type,
      ttl: 4,
      channelId: channelId,
      msgId: msgId,
      senderPublicKey: identity.publicKeyBytes,
      timestamp: ts,
      nickname: nickname,
      body: Uint8List.fromList(body),
      signature: sig,
    );
    dedup.remember(msgId);
    await transport.send(PacketCodec.encode(packet));
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

    if (packet.type == PacketType.ack || packet.type == PacketType.read) {
      final refHex = packet.body
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join();
      _acks.add(AckEvent(
        type: packet.type,
        refMsgIdHex: refHex,
        fromFingerprint: packet.shortFingerprint,
        channelId: packet.channelId,
      ));
    } else if (packet.type == PacketType.file) {
      await _handleFileFragment(packet, inbound.fromPeerId);
    } else if (packet.type == PacketType.chat) {
      String? plain;
      var isMedia = (packet.flags & MeshConstants.flagMedia) != 0;
      try {
        var bodyBytes = packet.body;
        if ((packet.flags & MeshConstants.flagEncrypted) != 0) {
          final key = channelKeys[packet.channelId];
          if (key == null) {
            plain = '🔒 encrypted (no key)';
          } else {
            bodyBytes =
                await GroupCrypto.decrypt(key32: key, sealed: bodyBytes);
            plain = utf8.decode(bodyBytes, allowMalformed: true);
            if (isMedia) {
              final chunk = MediaChunk.tryParse(plain);
              if (chunk == null) {
                try {
                  final env = MediaEnvelope.decode(plain);
                  plain = env.caption.isEmpty
                      ? '📎 ${env.filename}'
                      : '📎 ${env.filename}: ${env.caption}';
                } catch (_) {}
              }
            }
          }
        } else {
          plain = utf8.decode(bodyBytes, allowMalformed: true);
          if (isMedia) {
            // Keep chunk JSON as plainText for reassembly; UI labels later.
            final chunk = MediaChunk.tryParse(plain ?? '');
            if (chunk == null) {
              try {
                final env = MediaEnvelope.decode(plain!);
                plain = env.caption.isEmpty
                    ? '📎 ${env.filename}'
                    : '📎 ${env.filename}: ${env.caption}';
              } catch (_) {}
            }
          }
        }
      } catch (_) {
        _drops.add((DropReason.decryptFailed, packet.msgIdHex));
        plain = '🔒 decrypt failed';
      }

      _messages.add(ChatMessage(
        packet: packet,
        receivedAt: now(),
        fromPeerId: inbound.fromPeerId,
        isLocal: false,
        plainText: plain,
        isMedia: isMedia,
      ));

      // Auto delivery ACK
      if ((packet.flags & MeshConstants.flagNeedsAck) != 0) {
        unawaited(sendReceipt(
          type: PacketType.ack,
          refMsgId: packet.msgId,
          channelId: packet.channelId,
        ));
      }
    }

    // Ferry text only — file fragments must not re-flood.
    if (packet.type == PacketType.chat &&
        packet.ttl > 1 &&
        (packet.flags & MeshConstants.flagMedia) == 0) {
      ferry.enqueue(packet.copyWith(ttl: packet.ttl - 1));
    }

    if (packet.ttl <= 1) return;

    // Always forward file fragments (mesh multi-hop for images).
    // Rate-limit chat floods only.
    if (packet.type != PacketType.file && !rateLimiter.allow(now())) {
      _drops.add((DropReason.rateLimited, packet.msgIdHex));
      return;
    }

    final forwarded = packet.copyWith(ttl: packet.ttl - 1);
    await transport.send(
      PacketCodec.encode(forwarded),
      excludePeerId: inbound.fromPeerId,
    );
  }

  Future<void> _handleFileFragment(MeshPacket packet, String? fromPeerId) async {
    final frag = FileFragment.decode(packet.body);
    if (frag == null) {
      _drops.add((DropReason.badFormat, 'bad file fragment'));
      return;
    }
    final complete = _fileAssembler.add(frag);
    if (complete == null) {
      // Optional progress: only emit once at end to avoid multi-bubbles
      return;
    }

    final file = FilePacket.decode(complete);
    if (file == null) {
      _drops.add((DropReason.badFormat, 'bad file packet'));
      return;
    }

    final transferHex = FileFragment.idHex(frag.transferId);
    final isImage = file.mimeType.startsWith('image/');
    _messages.add(ChatMessage(
      packet: packet,
      receivedAt: now(),
      fromPeerId: fromPeerId,
      isLocal: false,
      plainText: '📎 ${file.fileName ?? 'file'}',
      isMedia: isImage,
      mediaBytes: isImage ? Uint8List.fromList(file.content) : null,
      mediaId: transferHex,
    ));
  }

  Future<void> dispose() async {
    await stop();
    await _messages.close();
    await _acks.close();
    await _drops.close();
  }
}
