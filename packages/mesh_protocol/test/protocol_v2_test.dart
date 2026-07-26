import 'dart:convert';
import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('group crypto roundtrip', () async {
    final key = GroupCrypto.randomKey();
    final sealed =
        await GroupCrypto.encrypt(key32: key, plaintext: utf8.encode('hi'));
    final open = await GroupCrypto.decrypt(key32: key, sealed: sealed);
    expect(utf8.decode(open), 'hi');
  });

  test('rate limiter blocks burst', () {
    final r = RateLimiter(maxEvents: 3, window: const Duration(seconds: 10));
    final t = DateTime.utc(2024, 1, 1);
    expect(r.allow(t), isTrue);
    expect(r.allow(t), isTrue);
    expect(r.allow(t), isTrue);
    expect(r.allow(t), isFalse);
  });

  test('ferry store enqueue/drain', () async {
    final id = await CryptoIdentity.generate();
    final ferry = FerryStore(maxQueue: 10);
    final msgId = CryptoIdentity.randomMsgId();
    final body = Uint8List.fromList(utf8.encode('ferry'));
    final payload = PacketCodec.signPayload(
      version: MeshConstants.version,
      type: PacketType.chat,
      channelId: 1,
      msgId: msgId,
      senderPublicKey: id.publicKeyBytes,
      timestamp: 1700000000,
      nicknameBytes: utf8.encode('a'),
      body: body,
    );
    final sig = await id.sign(payload);
    final p = MeshPacket(
      version: MeshConstants.version,
      type: PacketType.chat,
      ttl: 5,
      channelId: 1,
      msgId: msgId,
      senderPublicKey: id.publicKeyBytes,
      timestamp: 1700000000,
      nickname: 'a',
      body: body,
      signature: sig,
    );
    ferry.enqueue(p);
    expect(ferry.length, 1);
    final drained = ferry.drainForRelay();
    expect(drained.length, 1);
    expect(ferry.length, 0);
  });
}
