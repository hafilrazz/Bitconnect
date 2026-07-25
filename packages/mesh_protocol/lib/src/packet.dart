import 'dart:typed_data';

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
