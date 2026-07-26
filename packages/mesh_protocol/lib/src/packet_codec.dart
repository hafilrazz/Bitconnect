import 'dart:convert';
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
    // Accept v1 and current version for upgrade path.
    if (version < 1 || version > MeshConstants.version) {
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
