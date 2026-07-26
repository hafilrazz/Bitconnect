/// Protocol constants for Netless mesh v1.
class MeshConstants {
  static const int magic = 0x4E54; // 'NT'
  static const int version = 1;
  /// Multi-hop budget — more hops = larger *effective* mesh diameter.
  static const int maxTtl = 8;
  static const int maxNicknameBytes = 24;
  static const int maxBodyBytes = 200;
  static const int publicKeyLength = 32;
  static const int signatureLength = 64;
  static const int msgIdLength = 16;
  static const int defaultTimestampSkewSeconds = 2 * 60 * 60; // +/- 2h
  static const int defaultDedupCapacity = 10000;

  /// BLE-ish service id used by higher layers (documentation constant).
  static const String serviceUuid = '6e65746c-0001-4000-8000-00805f9b34fb';
  static const String characteristicUuid = '6e65746c-0002-4000-8000-00805f9b34fb';
}

enum PacketType {
  chat(1),
  announce(2);

  final int value;
  const PacketType(this.value);

  static PacketType? fromValue(int v) {
    for (final t in PacketType.values) {
      if (t.value == v) return t;
    }
    return null;
  }
}
