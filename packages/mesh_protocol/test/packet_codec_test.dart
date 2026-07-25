import 'dart:convert';
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
