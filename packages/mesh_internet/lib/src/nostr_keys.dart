import 'dart:convert';
import 'dart:math';

import 'package:bip340/bip340.dart' as bip340;
import 'package:crypto/crypto.dart';

/// Ephemeral or persistent secp256k1 key for outer Nostr event signatures.
/// Inner E2E payload uses X25519/Ed25519 — relays never see plaintext.
class NostrKeys {
  NostrKeys(this.privateKeyHex)
      : publicKeyHex = bip340.getPublicKey(privateKeyHex);

  final String privateKeyHex;
  final String publicKeyHex;

  static NostrKeys generate() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    // clamp for secp256k1: ensure non-zero
    if (bytes.every((b) => b == 0)) bytes[0] = 1;
    return NostrKeys(_toHex(bytes));
  }

  /// Deterministic Nostr key from app seed (domain-separated).
  static NostrKeys fromAppSeed(List<int> seed32) {
    final h = sha256.convert([...utf8.encode('netless-nostr-v1'), ...seed32]);
    return NostrKeys(_toHex(h.bytes));
  }

  String signEventId(String eventIdHex) {
    final aux = _toHex(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    return bip340.sign(privateKeyHex, eventIdHex, aux);
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

/// NIP-01 event helpers.
class NostrEvent {
  NostrEvent({
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    this.id = '',
    this.sig = '',
  });

  String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  String sig;

  /// Netless E2E DM kind — custom application kind.
  static const int kindE2eDm = 21000;

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'created_at': createdAt,
        'kind': kind,
        'tags': tags,
        'content': content,
        'sig': sig,
      };

  factory NostrEvent.fromJson(Map<String, dynamic> j) {
    final tags = <List<String>>[];
    for (final t in (j['tags'] as List? ?? const [])) {
      if (t is List) {
        tags.add(t.map((e) => e.toString()).toList());
      }
    }
    return NostrEvent(
      id: j['id'] as String? ?? '',
      pubkey: j['pubkey'] as String? ?? '',
      createdAt: j['created_at'] as int? ?? 0,
      kind: j['kind'] as int? ?? 0,
      tags: tags,
      content: j['content'] as String? ?? '',
      sig: j['sig'] as String? ?? '',
    );
  }

  static String computeId({
    required String pubkey,
    required int createdAt,
    required int kind,
    required List<List<String>> tags,
    required String content,
  }) {
    final serialized = jsonEncode([
      0,
      pubkey,
      createdAt,
      kind,
      tags,
      content,
    ]);
    return sha256.convert(utf8.encode(serialized)).bytes
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static NostrEvent signed({
    required NostrKeys keys,
    required int kind,
    required List<List<String>> tags,
    required String content,
    int? createdAt,
  }) {
    final ts = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final id = computeId(
      pubkey: keys.publicKeyHex,
      createdAt: ts,
      kind: kind,
      tags: tags,
      content: content,
    );
    final sig = keys.signEventId(id);
    return NostrEvent(
      id: id,
      pubkey: keys.publicKeyHex,
      createdAt: ts,
      kind: kind,
      tags: tags,
      content: content,
      sig: sig,
    );
  }
}
