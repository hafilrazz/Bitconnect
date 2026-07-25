import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

/// BLE transport scaffold.
///
/// Uses flutter_blue_plus central role to discover peers advertising the
/// Netless service and exchange packets over a GATT characteristic.
/// Full dual-role (peripheral + multi-central) mesh is intentionally
/// incremental: this class provides a working single-hop path and clear
/// extension points for peripheral advertising via platform channels later.
class BleMeshTransport implements MeshTransport {
  BleMeshTransport({
    this.serviceUuid = MeshConstants.serviceUuid,
    this.characteristicUuid = MeshConstants.characteristicUuid,
    this.maxPeers = 6,
  });

  final String serviceUuid;
  final String characteristicUuid;
  final int maxPeers;

  final _inbound = StreamController<MeshInbound>.broadcast();
  final Map<String, BluetoothDevice> _devices = {};
  final Map<String, BluetoothCharacteristic> _chars = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<OnConnectionStateChangedEvent>? _connSub;
  bool _up = false;

  Guid get _svcGuid => Guid(serviceUuid);
  Guid get _chrGuid => Guid(characteristicUuid);

  @override
  List<String> get peerIds => _chars.keys.toList();

  @override
  Stream<MeshInbound> get inbound => _inbound.stream;

  @override
  Future<void> start() async {
    if (_up) return;
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      throw StateError('Bluetooth not supported on this device');
    }
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 15));

    _connSub = FlutterBluePlus.events.onConnectionStateChanged.listen((e) {
      if (e.connectionState == BluetoothConnectionState.disconnected) {
        final id = e.device.remoteId.str;
        _devices.remove(id);
        _chars.remove(id);
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [_svcGuid],
      timeout: const Duration(seconds: 4),
      continuousUpdates: true,
    );
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
    // Keep periodic rescan
    unawaited(_scanLoop());
    _up = true;
  }

  Future<void> _scanLoop() async {
    while (_up) {
      try {
        if (!FlutterBluePlus.isScanningNow) {
          await FlutterBluePlus.startScan(
            withServices: [_svcGuid],
            timeout: const Duration(seconds: 4),
          );
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 6));
    }
  }

  Future<void> _onScanResults(List<ScanResult> results) async {
    if (!_up) return;
    for (final r in results) {
      if (_devices.length >= maxPeers) break;
      final id = r.device.remoteId.str;
      if (_devices.containsKey(id)) continue;
      try {
        await r.device.connect(timeout: const Duration(seconds: 8));
        final services = await r.device.discoverServices();
        BluetoothCharacteristic? target;
        for (final s in services) {
          if (s.uuid == _svcGuid) {
            for (final c in s.characteristics) {
              if (c.uuid == _chrGuid) {
                target = c;
                break;
              }
            }
          }
        }
        // Fallback: first writable+notify char if UUID not found (dev)
        target ??= services
            .expand((s) => s.characteristics)
            .cast<BluetoothCharacteristic?>()
            .firstWhere(
              (c) =>
                  c != null &&
                  (c.properties.write || c.properties.writeWithoutResponse) &&
                  c.properties.notify,
              orElse: () => null,
            );
        if (target == null) {
          await r.device.disconnect();
          continue;
        }
        await target.setNotifyValue(true);
        target.onValueReceived.listen((value) {
          if (value.isEmpty) return;
          _inbound.add(MeshInbound(
            fromPeerId: id,
            bytes: Uint8List.fromList(value),
          ));
        });
        _devices[id] = r.device;
        _chars[id] = target;
      } catch (_) {
        try {
          await r.device.disconnect();
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> stop() async {
    _up = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await _connSub?.cancel();
    _connSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    for (final d in _devices.values) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
    _devices.clear();
    _chars.clear();
  }

  @override
  Future<void> send(Uint8List data,
      {String? peerId, String? excludePeerId}) async {
    final entries = _chars.entries.where((e) {
      if (peerId != null) return e.key == peerId;
      if (excludePeerId != null) return e.key != excludePeerId;
      return true;
    });
    for (final e in entries) {
      try {
        final c = e.value;
        final withoutResp = c.properties.writeWithoutResponse;
        await c.write(data, withoutResponse: withoutResp);
      } catch (_) {}
    }
  }
}
