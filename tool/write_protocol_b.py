# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:/netless")

def w(rel, content):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content.replace("\r\n", "\n"), encoding="utf-8")
    print("wrote", rel)

w("packages/mesh_protocol/lib/src/packet_codec.dart", """import 'dart:convert';
import 'dart:typed_data';

import 'constants.dart';
import 'packet.dart';

/// Encode/decode Netless binary packets.
class PacketCodec {
  /// Bytes that are signed (excludes magic, ttl, flags, signature).
  static Uint8List signPayload({
    required int version,
    required PacketType type,
    required int channelId,
    required Uint8List msgId,
    required Uint8List senderPublicKey,
    required int timestamp,
    required List<int> nicknameBytes,
    required List<int> body,
  }) {
    final builder = BytesBuilder(copy: false);
    builder.addByte(version);
    builder.addByte(type.value);
    builder.addByte((channelId >> 8) & 0xff);
    builder.addByte(channelId & 0xff);
    builder.add(msgId);
    builder.add(senderPublicKey);
    builder.addByte((timestamp >> 24) & 0xff);
    builder.addByte((timestamp >> 16) & 0xff);
    builder.addByte((timestamp >> 8) & 0xff);
    builder.addByte(timestamp & 0xff);
    builder.add(nicknameBytes);
    builder.add(body);
    return builder.toBytes();
  }

  static Uint8List encode(MeshPacket packet) {
    final nick = utf8.encode(packet.nickname);
    if (nick.length > MeshConstants.maxNicknameBytes) {
      throw ArgumentError(
          'nickname exceeds ${MeshConstants.maxNicknameBytes} bytes');
    }
    if (packet.body.length > MeshConstants.maxBodyBytes) {
      throw ArgumentError('body exceeds ${MeshConstants.maxBodyBytes} bytes');
    }

    final builder = BytesBuilder(copy: false);
    builder.addByte((MeshConstants.magic >> 8) & 0xff);
    builder.addByte(MeshConstants.magic & 0xff);
    builder.addByte(packet.version);
    builder.addByte(packet.type.value);
    builder.addByte(packet.ttl & 0xff);
    builder.addByte(packet.flags & 0xff);
    builder.addByte((packet.channelId >> 8) & 0xff);
    builder.addByte(packet.channelId & 0xff);
    builder.add(packet.msgId);
    builder.add(packet.senderPublicKey);
    builder.addByte((packet.timestamp >> 24) & 0xff);
    builder.addByte((packet.timestamp >> 16) & 0xff);
    builder.addByte((packet.timestamp >> 8) & 0xff);
    builder.addByte(packet.timestamp & 0xff);
    builder.addByte(nick.length);
    builder.add(nick);
    builder.addByte((packet.body.length >> 8) & 0xff);
    builder.addByte(packet.body.length & 0xff);
    builder.add(packet.body);
    builder.add(packet.signature);
    return builder.toBytes();
  }

  static MeshPacket decode(Uint8List data) {
    if (data.length < 2 + 1 + 1 + 1 + 1 + 2 + 16 + 32 + 4 + 1 + 2 + 64) {
      throw FormatException('packet too short: ${data.length}');
    }
    var o = 0;
    final magic = (data[o] << 8) | data[o + 1];
    o += 2;
    if (magic != MeshConstants.magic) {
      throw FormatException('bad magic: 0x${magic.toRadixString(16)}');
    }
    final version = data[o++];
    if (version != MeshConstants.version) {
      throw FormatException('unsupported version: $version');
    }
    final typeVal = data[o++];
    final type = PacketType.fromValue(typeVal);
    if (type == null) {
      throw FormatException('unknown type: $typeVal');
    }
    final ttl = data[o++];
    final flags = data[o++];
    final channelId = (data[o] << 8) | data[o + 1];
    o += 2;
    final msgId = Uint8List.fromList(data.sublist(o, o + 16));
    o += 16;
    final senderPk = Uint8List.fromList(data.sublist(o, o + 32));
    o += 32;
    final timestamp = (data[o] << 24) |
        (data[o + 1] << 16) |
        (data[o + 2] << 8) |
        data[o + 3];
    o += 4;
    final nickLen = data[o++];
    if (nickLen > MeshConstants.maxNicknameBytes) {
      throw FormatException('nickname too long: $nickLen');
    }
    if (o + nickLen > data.length) {
      throw FormatException('truncated nickname');
    }
    final nickBytes = data.sublist(o, o + nickLen);
    o += nickLen;
    final nickname = utf8.decode(nickBytes, allowMalformed: false);
    if (o + 2 > data.length) throw FormatException('truncated body length');
    final bodyLen = (data[o] << 8) | data[o + 1];
    o += 2;
    if (bodyLen > MeshConstants.maxBodyBytes) {
      throw FormatException('body too long: $bodyLen');
    }
    if (o + bodyLen + MeshConstants.signatureLength > data.length) {
      throw FormatException('truncated body/signature');
    }
    final body = Uint8List.fromList(data.sublist(o, o + bodyLen));
    o += bodyLen;
    final signature =
        Uint8List.fromList(data.sublist(o, o + MeshConstants.signatureLength));

    return MeshPacket(
      version: version,
      type: type,
      ttl: ttl,
      flags: flags,
      channelId: channelId,
      msgId: msgId,
      senderPublicKey: senderPk,
      timestamp: timestamp,
      nickname: nickname,
      body: body,
      signature: signature,
    );
  }
}
""")

w("packages/mesh_protocol/lib/src/crypto_identity.dart", """import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'constants.dart';
import 'packet.dart';
import 'packet_codec.dart';

/// Ed25519 identity for signing public posts.
class CryptoIdentity {
  CryptoIdentity._(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  static final _algo = Ed25519();

  static Future<CryptoIdentity> generate() async {
    final kp = await _algo.newKeyPair();
    final pub = await kp.extractPublicKey();
    return CryptoIdentity._(kp, Uint8List.fromList(pub.bytes));
  }

  static Future<CryptoIdentity> fromSeed(List<int> seed32) async {
    if (seed32.length != 32) {
      throw ArgumentError('seed must be 32 bytes');
    }
    final kp = await _algo.newKeyPairFromSeed(seed32);
    final pub = await kp.extractPublicKey();
    return CryptoIdentity._(kp, Uint8List.fromList(pub.bytes));
  }

  /// Export raw 32-byte seed for secure storage.
  Future<Uint8List> exportSeed() async {
    final seed = await keyPair.extractPrivateKeyBytes();
    return Uint8List.fromList(seed);
  }

  String get shortFingerprint {
    return publicKeyBytes
        .take(4)
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Uint8List> sign(List<int> payload) async {
    final sig = await _algo.sign(payload, keyPair: keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  static Future<bool> verify({
    required List<int> payload,
    required List<int> signature,
    required List<int> publicKey,
  }) async {
    try {
      return await _algo.verify(
        payload,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> verifyPacket(MeshPacket packet) async {
    final nick = packet.nickname.codeUnits; // use utf8 in callers via codec path
    // Re-encode nickname properly:
    final nickBytes = Uint8List.fromList(
      // ignore: unnecessary_cast
      (packet.nickname).codeUnits.isEmpty
          ? <int>[]
          : _utf8(packet.nickname),
    );
    final payload = PacketCodec.signPayload(
      version: packet.version,
      type: packet.type,
      channelId: packet.channelId,
      msgId: packet.msgId,
      senderPublicKey: packet.senderPublicKey,
      timestamp: packet.timestamp,
      nicknameBytes: nickBytes,
      body: packet.body,
    );
    return verify(
      payload: payload,
      signature: packet.signature,
      publicKey: packet.senderPublicKey,
    );
  }

  static List<int> _utf8(String s) {
    return s.codeUnits.length == s.length && s.codeUnits.every((c) => c < 128)
        ? s.codeUnits
        : (s.runes.every((r) => r < 128)
            ? s.codeUnits
            : _encodeUtf8(s));
  }

  static List<int> _encodeUtf8(String s) {
    // Manual utf8 via code points for non-ASCII nicknames.
    final out = <int>[];
    for (final r in s.runes) {
      if (r <= 0x7f) {
        out.add(r);
      } else if (r <= 0x7ff) {
        out.add(0xc0 | (r >> 6));
        out.add(0x80 | (r & 0x3f));
      } else if (r <= 0xffff) {
        out.add(0xe0 | (r >> 12));
        out.add(0x80 | ((r >> 6) & 0x3f));
        out.add(0x80 | (r & 0x3f));
      } else {
        out.add(0xf0 | (r >> 18));
        out.add(0x80 | ((r >> 12) & 0x3f));
        out.add(0x80 | ((r >> 6) & 0x3f));
        out.add(0x80 | (r & 0x3f));
      }
    }
    return out;
  }

  /// Random 16-byte message id.
  static Uint8List randomMsgId([Random? random]) {
    final r = random ?? Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
  }
}
""")

# Fix crypto to use dart:convert utf8 properly - rewrite cleaner version
w("packages/mesh_protocol/lib/src/crypto_identity.dart", """import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'packet.dart';
import 'packet_codec.dart';

/// Ed25519 identity for signing public posts.
class CryptoIdentity {
  CryptoIdentity._(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  static final _algo = Ed25519();

  static Future<CryptoIdentity> generate() async {
    final kp = await _algo.newKeyPair();
    final pub = await kp.extractPublicKey();
    return CryptoIdentity._(kp, Uint8List.fromList(pub.bytes));
  }

  static Future<CryptoIdentity> fromSeed(List<int> seed32) async {
    if (seed32.length != 32) {
      throw ArgumentError('seed must be 32 bytes');
    }
    final kp = await _algo.newKeyPairFromSeed(seed32);
    final pub = await kp.extractPublicKey();
    return CryptoIdentity._(kp, Uint8List.fromList(pub.bytes));
  }

  /// Export raw 32-byte seed for secure storage.
  Future<Uint8List> exportSeed() async {
    final seed = await keyPair.extractPrivateKeyBytes();
    return Uint8List.fromList(seed);
  }

  String get shortFingerprint {
    return publicKeyBytes
        .take(4)
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Uint8List> sign(List<int> payload) async {
    final sig = await _algo.sign(payload, keyPair: keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  static Future<bool> verify({
    required List<int> payload,
    required List<int> signature,
    required List<int> publicKey,
  }) async {
    try {
      return await _algo.verify(
        payload,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> verifyPacket(MeshPacket packet) async {
    final nickBytes = utf8.encode(packet.nickname);
    final payload = PacketCodec.signPayload(
      version: packet.version,
      type: packet.type,
      channelId: packet.channelId,
      msgId: packet.msgId,
      senderPublicKey: packet.senderPublicKey,
      timestamp: packet.timestamp,
      nicknameBytes: nickBytes,
      body: packet.body,
    );
    return verify(
      payload: payload,
      signature: packet.signature,
      publicKey: packet.senderPublicKey,
    );
  }

  /// Random 16-byte message id.
  static Uint8List randomMsgId([Random? random]) {
    final r = random ?? Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
  }
}
""")

w("packages/mesh_protocol/lib/src/dedup_cache.dart", """import 'dart:collection';
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
""")

print("protocol B ok")
