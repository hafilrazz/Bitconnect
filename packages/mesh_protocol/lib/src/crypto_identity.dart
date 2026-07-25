import 'dart:convert';
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
