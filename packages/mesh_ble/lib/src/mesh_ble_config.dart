/// Tunables aimed at maximizing practical BLE mesh reach.
///
/// Phone radios still top out around tens of meters per hop; multi-hop + high
/// TX/scan aggressiveness is what extends *effective* range.
class MeshBleConfig {
  /// Concurrent GATT connections as central (plus native peripheral centrals).
  static const int maxPeers = 10;

  /// Prefer longer continuous scan windows so distant ads are less often missed.
  static const Duration scanWindow = Duration(seconds: 12);

  /// How often we restart scan if the OS stops it.
  static const Duration scanRestartInterval = Duration(seconds: 3);

  /// GATT connect timeout (weaker / farther devices need longer).
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Target MTU for fewer radio round-trips (negotiated down if needed).
  static const int preferredMtu = 517;

  /// Minimum RSSI to attempt connect. Very weak ads waste connection slots;
  /// -95 dBm still allows edge-of-range peers for multi-hop.
  static const int minConnectRssi = -95;
}
