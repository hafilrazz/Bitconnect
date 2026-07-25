import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdentityStore {
  IdentityStore({
    FlutterSecureStorage? secure,
  }) : _secure = secure ?? const FlutterSecureStorage();

  static const _seedKey = 'netless_ed25519_seed_b64';
  static const _nickKey = 'netless_nickname';

  final FlutterSecureStorage _secure;

  Future<CryptoIdentity> loadOrCreateIdentity() async {
    final existing = await _secure.read(key: _seedKey);
    if (existing != null && existing.isNotEmpty) {
      final seed = base64Decode(existing);
      return CryptoIdentity.fromSeed(seed);
    }
    final id = await CryptoIdentity.generate();
    final seed = await id.exportSeed();
    await _secure.write(key: _seedKey, value: base64Encode(seed));
    return id;
  }

  Future<String?> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nickKey);
  }

  Future<void> setNickname(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nickKey, nickname.trim());
  }
}
