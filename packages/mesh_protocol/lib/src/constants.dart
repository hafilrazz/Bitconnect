/// Protocol constants for Bitconnect mesh v2 (wire magic still NT).
class MeshConstants {
  static const int magic = 0x4E54; // 'NT'
  static const int version = 2;
  /// Multi-hop budget — more hops = larger *effective* mesh diameter.
  static const int maxTtl = 8;
  static const int maxNicknameBytes = 24;
  /// Larger payloads for media chunks / richer text (still BLE-friendly when chunked).
  static const int maxBodyBytes = 1800;
  static const int publicKeyLength = 32;
  static const int signatureLength = 64;
  static const int msgIdLength = 16;
  static const int defaultTimestampSkewSeconds = 2 * 60 * 60; // +/- 2h
  static const int defaultDedupCapacity = 20000;

  /// Flood control: max outbound chat packets per window.
  /// Higher to allow multi-chunk media without false rate-limit failures.
  static const int rateLimitMaxPackets = 40;
  static const int rateLimitWindowMs = 15000;

  /// Ferry store-and-forward: max queued messages for offline peers.
  static const int ferryMaxQueue = 64;
  static const int ferryMaxAgeSeconds = 48 * 60 * 60;

  /// BLE service identity.
  static const String serviceUuid = '6e65746c-0001-4000-8000-00805f9b34fb';
  static const String characteristicUuid = '6e65746c-0002-4000-8000-00805f9b34fb';

  /// Flags bitfield
  static const int flagEncrypted = 1 << 0; // body is sealed for channel/group
  static const int flagMedia = 1 << 1; // body is media envelope JSON
  static const int flagNeedsAck = 1 << 2;
}

enum PacketType {
  chat(1),
  announce(2),
  ack(3), // delivery acknowledgment
  read(4), // read receipt
  ferry(5), // store-and-forward wrapper (future / passthrough)
  /// Binary file fragment (images / files over mesh).
  file(6);

  final int value;
  const PacketType(this.value);

  static PacketType? fromValue(int v) {
    for (final t in PacketType.values) {
      if (t.value == v) return t;
    }
    return null;
  }
}

/// Power / Friend-LPN style duty modes (application-level).
enum PowerMode {
  /// Continuous scan/advertise — best range, higher battery.
  performance,
  /// Balanced windows.
  balanced,
  /// Low-power node: sparse scan, longer sleep (LPN-like).
  saver,
}
