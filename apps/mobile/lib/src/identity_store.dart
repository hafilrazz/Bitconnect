import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppIdentity {
  AppIdentity({
    required this.sign,
    required this.enc,
    required this.signSeed,
    required this.encSeed,
    required this.nickname,
  });

  final CryptoIdentity sign;
  final EncryptionIdentity enc;
  final Uint8List signSeed;
  final Uint8List encSeed;
  final String nickname;

  /// Shareable address for internet E2E DMs (X25519 pubkey hex).
  String get netlessId => enc.publicKeyHex;
}

class IdentityStore {
  IdentityStore({
    FlutterSecureStorage? secure,
  }) : _secure = secure ?? const FlutterSecureStorage();

  static const _signSeedKey = 'netless_ed25519_seed_b64';
  static const _encSeedKey = 'netless_x25519_seed_b64';
  static const _nickKey = 'netless_nickname';
  static const _contactsKey = 'netless_contacts_json';

  final FlutterSecureStorage _secure;

  Future<AppIdentity> loadOrCreate({String nickname = 'anon'}) async {
    final signSeed = await _loadOrCreateSeed(_signSeedKey);
    final encSeed = await _loadOrCreateSeed(_encSeedKey);
    final sign = await CryptoIdentity.fromSeed(signSeed);
    final enc = await EncryptionIdentity.fromSeed(encSeed);
    final nick = (await getNickname()) ?? nickname;
    return AppIdentity(
      sign: sign,
      enc: enc,
      signSeed: signSeed,
      encSeed: encSeed,
      nickname: nick,
    );
  }

  /// Back-compat for older providers.
  Future<CryptoIdentity> loadOrCreateIdentity() async {
    final app = await loadOrCreate();
    return app.sign;
  }

  Future<Uint8List> _loadOrCreateSeed(String key) async {
    final existing = await _secure.read(key: key);
    if (existing != null && existing.isNotEmpty) {
      return Uint8List.fromList(base64Decode(existing));
    }
    // Generate via identity helpers
    if (key == _signSeedKey) {
      final id = await CryptoIdentity.generate();
      final seed = await id.exportSeed();
      await _secure.write(key: key, value: base64Encode(seed));
      return seed;
    } else {
      final id = await EncryptionIdentity.generate();
      final seed = await id.exportSeed();
      await _secure.write(key: key, value: base64Encode(seed));
      return seed;
    }
  }

  Future<String?> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nickKey);
  }

  Future<void> setNickname(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nickKey, nickname.trim());
  }

  Future<List<Contact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_contactsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Contact.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveContacts(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _contactsKey,
      jsonEncode(contacts.map((c) => c.toJson()).toList()),
    );
  }
}

class Contact {
  Contact({required this.name, required this.netlessId});

  final String name;
  final String netlessId;

  Map<String, dynamic> toJson() => {'name': name, 'id': netlessId};

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        name: j['name'] as String? ?? 'contact',
        netlessId: (j['id'] as String? ?? '').toLowerCase(),
      );
}
