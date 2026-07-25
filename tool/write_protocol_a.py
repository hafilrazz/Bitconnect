# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:/netless")

def w(rel, content):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content.replace("\r\n", "\n"), encoding="utf-8")
    print("wrote", rel)

w("packages/mesh_protocol/pubspec.yaml", """name: mesh_protocol
description: Netless mesh packet codec, crypto, and gossip logic (pure Dart).
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  cryptography: ^2.7.0
  meta: ^1.12.0

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
""")

w("packages/mesh_protocol/analysis_options.yaml", """include: package:lints/recommended.yaml
""")

w("packages/mesh_protocol/lib/mesh_protocol.dart", """library mesh_protocol;

export 'src/channel.dart';
export 'src/constants.dart';
export 'src/crypto_identity.dart';
export 'src/dedup_cache.dart';
export 'src/mesh_node.dart';
export 'src/packet.dart';
export 'src/packet_codec.dart';
""")

w("packages/mesh_protocol/lib/src/constants.dart", """/// Protocol constants for Netless mesh v1.
class MeshConstants {
  static const int magic = 0x4E54; // 'NT'
  static const int version = 1;
  static const int maxTtl = 7;
  static const int maxNicknameBytes = 24;
  static const int maxBodyBytes = 200;
  static const int publicKeyLength = 32;
  static const int signatureLength = 64;
  static const int msgIdLength = 16;
  static const int defaultTimestampSkewSeconds = 2 * 60 * 60; // +/- 2h
  static const int defaultDedupCapacity = 10000;

  /// BLE-ish service id used by higher layers (documentation constant).
  static const String serviceUuid = '6e65746c-0001-4000-8000-00805f9b34fb';
  static const String characteristicUuid = '6e65746c-0002-4000-8000-00805f9b34fb';
}

enum PacketType {
  chat(1),
  announce(2);

  final int value;
  const PacketType(this.value);

  static PacketType? fromValue(int v) {
    for (final t in PacketType.values) {
      if (t.value == v) return t;
    }
    return null;
  }
}
""")

w("packages/mesh_protocol/lib/src/channel.dart", """import 'dart:convert';

/// Well-known and derived channel ids.
class Channels {
  static const int local = 1;
  static const String localName = '#local';

  /// Stable 16-bit id from channel name (FNV-1a 32 truncated).
  static int idForName(String name) {
    final n = name.trim().toLowerCase();
    if (n == localName || n == 'local' || n == '#local') return local;
    final bytes = utf8.encode(n.startsWith('#') ? n : '#$n');
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    final id = hash & 0xffff;
    return id == 0 ? 1 : id;
  }
}
""")

w("packages/mesh_protocol/lib/src/packet.dart", """import 'dart:typed_data';

import 'constants.dart';

/// Immutable mesh packet (after decode or before encode).
class MeshPacket {
  final int version;
  final PacketType type;
  final int ttl;
  final int flags;
  final int channelId;
  final Uint8List msgId;
  final Uint8List senderPublicKey;
  final int timestamp;
  final String nickname;
  final Uint8List body;
  final Uint8List signature;

  MeshPacket({
    required this.version,
    required this.type,
    required this.ttl,
    this.flags = 0,
    required this.channelId,
    required this.msgId,
    required this.senderPublicKey,
    required this.timestamp,
    required this.nickname,
    required this.body,
    required this.signature,
  }) {
    if (msgId.length != MeshConstants.msgIdLength) {
      throw ArgumentError('msgId must be ${MeshConstants.msgIdLength} bytes');
    }
    if (senderPublicKey.length != MeshConstants.publicKeyLength) {
      throw ArgumentError(
          'senderPublicKey must be ${MeshConstants.publicKeyLength} bytes');
    }
    if (signature.length != MeshConstants.signatureLength) {
      throw ArgumentError(
          'signature must be ${MeshConstants.signatureLength} bytes');
    }
  }

  String get bodyText => String.fromCharCodes(body);

  MeshPacket copyWith({
    int? version,
    PacketType? type,
    int? ttl,
    int? flags,
    int? channelId,
    Uint8List? msgId,
    Uint8List? senderPublicKey,
    int? timestamp,
    String? nickname,
    Uint8List? body,
    Uint8List? signature,
  }) {
    return MeshPacket(
      version: version ?? this.version,
      type: type ?? this.type,
      ttl: ttl ?? this.ttl,
      flags: flags ?? this.flags,
      channelId: channelId ?? this.channelId,
      msgId: msgId ?? this.msgId,
      senderPublicKey: senderPublicKey ?? this.senderPublicKey,
      timestamp: timestamp ?? this.timestamp,
      nickname: nickname ?? this.nickname,
      body: body ?? this.body,
      signature: signature ?? this.signature,
    );
  }

  String get shortFingerprint {
    final b = senderPublicKey;
    final hex = b
        .take(4)
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
    return hex;
  }

  String get msgIdHex =>
      msgId.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}
""")

print("protocol part A ok")
