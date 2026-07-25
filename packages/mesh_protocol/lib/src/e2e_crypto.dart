import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_identity.dart';

/// Static X25519 encryption identity (separate from Ed25519 signing identity).
class EncryptionIdentity {
  EncryptionIdentity._(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  static final _x25519 = X25519();

  static Future<EncryptionIdentity> generate() async {
    final kp = await _x25519.newKeyPair();
    final pub = await kp.extractPublicKey();
    return EncryptionIdentity._(kp, Uint8List.fromList(pub.bytes));
  }

  static Future<EncryptionIdentity> fromSeed(List<int> seed32) async {
    if (seed32.length != 32) {
      throw ArgumentError('seed must be 32 bytes');
    }
    final kp = await _x25519.newKeyPairFromSeed(seed32);
    final pub = await kp.extractPublicKey();
    return EncryptionIdentity._(kp, Uint8List.fromList(pub.bytes));
  }

  Future<Uint8List> exportSeed() async {
    final seed = await keyPair.extractPrivateKeyBytes();
    return Uint8List.fromList(seed);
  }

  String get publicKeyHex => _toHex(publicKeyBytes);

  static Uint8List publicKeyFromHex(String hex) {
    final cleaned = hex.trim().toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (cleaned.length != 64) {
      throw FormatException('expected 32-byte hex public key, got ${cleaned.length ~/ 2}');
    }
    return Uint8List.fromList([
      for (var i = 0; i < cleaned.length; i += 2)
        int.parse(cleaned.substring(i, i + 2), radix: 16),
    ]);
  }
}

/// Pure end-to-end sealed box. Relays only see ciphertext + public metadata.
///
/// Construction:
/// - Ephemeral X25519 keypair per message
/// - ECDH with recipient static X25519 pubkey
/// - HKDF-SHA256 → ChaCha20-Poly1305 key
/// - Ed25519 signature over AAD so recipient authenticates sender
class E2eBox {
  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aead = Chacha20.poly1305Aead();

  /// Seal [plaintext] for [recipientX25519Pk].
  static Future<E2eSealedMessage> seal({
    required CryptoIdentity senderSign,
    required EncryptionIdentity senderEnc,
    required Uint8List recipientX25519Pk,
    required String plaintext,
    String? nickname,
  }) async {
    final eph = await _x25519.newKeyPair();
    final ephPub = await eph.extractPublicKey();
    final ephPubBytes = Uint8List.fromList(ephPub.bytes);

    final shared = await _x25519.sharedSecretKey(
      keyPair: eph,
      remotePublicKey: SimplePublicKey(recipientX25519Pk, type: KeyPairType.x25519),
    );

    final salt = Uint8List.fromList(utf8.encode('netless-e2e-v1'));
    final info = Uint8List.fromList([
      ...senderSign.publicKeyBytes,
      ...ephPubBytes,
      ...recipientX25519Pk,
    ]);
    final okm = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: salt,
      info: info,
    );

    final nonce = _randomBytes(12);
    final clear = utf8.encode(plaintext);
    final secretBox = await _aead.encrypt(
      clear,
      secretKey: okm,
      nonce: nonce,
    );

    final cipherAndMac = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    final nick = nickname ?? '';
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final aad = _canonicalAad(
      version: 1,
      senderSignPk: senderSign.publicKeyBytes,
      senderEncPk: senderEnc.publicKeyBytes,
      recipientEncPk: recipientX25519Pk,
      ephPk: ephPubBytes,
      timestamp: ts,
      nickname: nick,
      nonce: nonce,
      ciphertext: cipherAndMac,
    );
    final sig = await senderSign.sign(aad);

    return E2eSealedMessage(
      version: 1,
      senderSignPk: senderSign.publicKeyBytes,
      senderEncPk: senderEnc.publicKeyBytes,
      recipientEncPk: recipientX25519Pk,
      ephPk: ephPubBytes,
      timestamp: ts,
      nickname: nick,
      nonce: nonce,
      ciphertext: cipherAndMac,
      signature: sig,
    );
  }

  /// Open a sealed message with our encryption identity. Verifies Ed25519 sig.
  static Future<E2eOpenedMessage> open({
    required EncryptionIdentity recipientEnc,
    required E2eSealedMessage sealed,
  }) async {
    if (sealed.version != 1) {
      throw StateError('unsupported e2e version ${sealed.version}');
    }
    if (!_bytesEqual(sealed.recipientEncPk, recipientEnc.publicKeyBytes)) {
      throw StateError('message not addressed to this identity');
    }

    final aad = _canonicalAad(
      version: sealed.version,
      senderSignPk: sealed.senderSignPk,
      senderEncPk: sealed.senderEncPk,
      recipientEncPk: sealed.recipientEncPk,
      ephPk: sealed.ephPk,
      timestamp: sealed.timestamp,
      nickname: sealed.nickname,
      nonce: sealed.nonce,
      ciphertext: sealed.ciphertext,
    );
    final okSig = await CryptoIdentity.verify(
      payload: aad,
      signature: sealed.signature,
      publicKey: sealed.senderSignPk,
    );
    if (!okSig) {
      throw StateError('invalid sender signature (E2E authenticity failed)');
    }

    final shared = await _x25519.sharedSecretKey(
      keyPair: recipientEnc.keyPair,
      remotePublicKey:
          SimplePublicKey(sealed.ephPk, type: KeyPairType.x25519),
    );
    final salt = Uint8List.fromList(utf8.encode('netless-e2e-v1'));
    final info = Uint8List.fromList([
      ...sealed.senderSignPk,
      ...sealed.ephPk,
      ...sealed.recipientEncPk,
    ]);
    final okm = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: salt,
      info: info,
    );

    if (sealed.ciphertext.length < 16) {
      throw StateError('ciphertext too short');
    }
    final macStart = sealed.ciphertext.length - 16;
    final cipherText = sealed.ciphertext.sublist(0, macStart);
    final macBytes = sealed.ciphertext.sublist(macStart);

    final clear = await _aead.decrypt(
      SecretBox(cipherText, nonce: sealed.nonce, mac: Mac(macBytes)),
      secretKey: okm,
    );

    return E2eOpenedMessage(
      plaintext: utf8.decode(clear),
      senderSignPk: sealed.senderSignPk,
      senderEncPk: sealed.senderEncPk,
      nickname: sealed.nickname,
      timestamp: sealed.timestamp,
    );
  }

  static Uint8List _canonicalAad({
    required int version,
    required Uint8List senderSignPk,
    required Uint8List senderEncPk,
    required Uint8List recipientEncPk,
    required Uint8List ephPk,
    required int timestamp,
    required String nickname,
    required Uint8List nonce,
    required Uint8List ciphertext,
  }) {
    final b = BytesBuilder(copy: false);
    b.addByte(version);
    b.add(senderSignPk);
    b.add(senderEncPk);
    b.add(recipientEncPk);
    b.add(ephPk);
    b.addByte((timestamp >> 24) & 0xff);
    b.addByte((timestamp >> 16) & 0xff);
    b.addByte((timestamp >> 8) & 0xff);
    b.addByte(timestamp & 0xff);
    final nick = utf8.encode(nickname);
    b.addByte(nick.length & 0xff);
    b.add(nick);
    b.add(nonce);
    b.add(ciphertext);
    return b.toBytes();
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}

class E2eSealedMessage {
  E2eSealedMessage({
    required this.version,
    required this.senderSignPk,
    required this.senderEncPk,
    required this.recipientEncPk,
    required this.ephPk,
    required this.timestamp,
    required this.nickname,
    required this.nonce,
    required this.ciphertext,
    required this.signature,
  });

  final int version;
  final Uint8List senderSignPk;
  final Uint8List senderEncPk;
  final Uint8List recipientEncPk;
  final Uint8List ephPk;
  final int timestamp;
  final String nickname;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List signature;

  Map<String, dynamic> toJson() => {
        'v': version,
        'ssp': _toHex(senderSignPk),
        'sep': _toHex(senderEncPk),
        'rep': _toHex(recipientEncPk),
        'eph': _toHex(ephPk),
        'ts': timestamp,
        'nick': nickname,
        'nonce': base64Encode(nonce),
        'ct': base64Encode(ciphertext),
        'sig': _toHex(signature),
      };

  factory E2eSealedMessage.fromJson(Map<String, dynamic> j) {
    return E2eSealedMessage(
      version: j['v'] as int? ?? 1,
      senderSignPk: EncryptionIdentity.publicKeyFromHex(j['ssp'] as String),
      senderEncPk: EncryptionIdentity.publicKeyFromHex(j['sep'] as String),
      recipientEncPk: EncryptionIdentity.publicKeyFromHex(j['rep'] as String),
      ephPk: EncryptionIdentity.publicKeyFromHex(j['eph'] as String),
      timestamp: j['ts'] as int? ?? 0,
      nickname: j['nick'] as String? ?? '',
      nonce: Uint8List.fromList(base64Decode(j['nonce'] as String)),
      ciphertext: Uint8List.fromList(base64Decode(j['ct'] as String)),
      signature: _hexToBytes(j['sig'] as String),
    );
  }

  String encode() => jsonEncode(toJson());

  static E2eSealedMessage decode(String s) =>
      E2eSealedMessage.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

class E2eOpenedMessage {
  E2eOpenedMessage({
    required this.plaintext,
    required this.senderSignPk,
    required this.senderEncPk,
    required this.nickname,
    required this.timestamp,
  });

  final String plaintext;
  final Uint8List senderSignPk;
  final Uint8List senderEncPk;
  final String nickname;
  final int timestamp;

  String get senderFingerprint =>
      senderSignPk.take(4).map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

String _toHex(List<int> bytes) =>
    bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexToBytes(String hex) {
  final cleaned = hex.trim().toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
  if (cleaned.length.isOdd) {
    throw FormatException('odd hex length');
  }
  return Uint8List.fromList([
    for (var i = 0; i < cleaned.length; i += 2)
      int.parse(cleaned.substring(i, i + 2), radix: 16),
  ]);
}
