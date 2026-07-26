import 'dart:convert';

/// Well-known and derived channel ids.
class Channels {
  static const int local = 1;
  static const String localName = '#local';

  /// Stable 16-bit id from channel name (FNV-1a 32 truncated).
  static int idForName(String name) {
    final n = name.trim().toLowerCase();
    if (n == localName || n == 'local' || n == '#local') return local;
    final bytes = utf8.encode(n.startsWith('#') ? n : '#$n');
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    final id = hash & 0xffff;
    return id == 0 ? 1 : id;
  }

  static String normalizeName(String name) {
    final t = name.trim();
    if (t.isEmpty) return localName;
    return t.startsWith('#') ? t.toLowerCase() : '#${t.toLowerCase()}';
  }
}

/// Optional local channel encryption key (shared secret for public-ish rooms).
class ChannelCrypto {
  /// Derive a display label for a channel key fingerprint.
  static String keyFingerprint(List<int> keyBytes) {
    return keyBytes
        .take(4)
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
