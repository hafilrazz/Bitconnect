import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Symmetric encryption for local encrypted channels / group E2E.
class GroupCrypto {
  static final _aead = Chacha20.poly1305Aead();

  static Uint8List randomKey([Random? r]) {
    final rnd = r ?? Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
  }

  static Future<Uint8List> encrypt({
    required List<int> key32,
    required List<int> plaintext,
  }) async {
    final nonce = Uint8List.fromList(
        List<int>.generate(12, (_) => Random.secure().nextInt(256)));
    final box = await _aead.encrypt(
      plaintext,
      secretKey: SecretKey(key32),
      nonce: nonce,
    );
    return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Uint8List> decrypt({
    required List<int> key32,
    required List<int> sealed,
  }) async {
    final bytes = sealed;
    if (bytes.length < 12 + 16) {
      throw StateError('sealed payload too short');
    }
    final nonce = bytes.sublist(0, 12);
    final mac = bytes.sublist(bytes.length - 16);
    final ct = bytes.sublist(12, bytes.length - 16);
    final clear = await _aead.decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key32),
    );
    return Uint8List.fromList(clear);
  }

  static String encodeKeyB64(List<int> key) => base64UrlEncode(key);
  static Uint8List decodeKeyB64(String s) =>
      Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));
}

/// Media envelope stored in packet body when flagMedia is set.
class MediaEnvelope {
  MediaEnvelope({
    required this.mime,
    required this.filename,
    required this.dataB64,
    this.caption = '',
  });

  final String mime;
  final String filename;
  final String dataB64;
  final String caption;

  Map<String, dynamic> toJson() => {
        'mime': mime,
        'name': filename,
        'data': dataB64,
        'cap': caption,
      };

  factory MediaEnvelope.fromJson(Map<String, dynamic> j) => MediaEnvelope(
        mime: j['mime'] as String? ?? 'application/octet-stream',
        filename: j['name'] as String? ?? 'file',
        dataB64: j['data'] as String? ?? '',
        caption: j['cap'] as String? ?? '',
      );

  String encode() => jsonEncode(toJson());
  static MediaEnvelope decode(String s) =>
      MediaEnvelope.fromJson(jsonDecode(s) as Map<String, dynamic>);

  Uint8List get bytes => base64Decode(dataB64);
}
