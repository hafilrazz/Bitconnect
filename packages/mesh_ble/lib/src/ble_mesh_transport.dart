import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import 'mesh_ble_config.dart';

/// Central-role BLE transport (non-Android dual-role path / fallback).
///
/// Aggressive low-latency scan + RSSI-ordered connects for better reach.
class BleMeshTransport implements MeshTransport {
  BleMeshTransport({
    this.serviceUuid = MeshConstants.serviceUuid,
    this.characteristicUuid = MeshConstants.characteristicUuid,
    this.maxPeers = MeshBleConfig.maxPeers,
  });

  final String serviceUuid;
  final String characteristicUuid;
  final int maxPeers;

  final _inbound = StreamController<MeshInbound>.broadcast();
  final Map<String, BluetoothDevice> _devices = {};
  final Map<String, BluetoothCharacteristic> _chars = {};
  final Set<String> _connecting = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<OnConnectionStateChangedEvent>? _connSub;
  bool _up = false;
  bool _handlingScan = false;

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
        _connecting.remove(id);
      }
    });

    await _startScan();
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
    unawaited(_scanLoop());
    _up = true;
  }

  Future<void> _startScan() async {
    try {
      await FlutterBluePlus.startScan(
        withServices: [_svcGuid],
        timeout: MeshBleConfig.scanWindow,
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (_) {
      try {
        await FlutterBluePlus.startScan(
          timeout: MeshBleConfig.scanWindow,
          continuousUpdates: true,
          androidScanMode: AndroidScanMode.lowLatency,
        );
      } catch (_) {}
    }
  }

  Future<void> _scanLoop() async {
    while (_up) {
      try {
        if (!FlutterBluePlus.isScanningNow) {
          await _startScan();
        }
      } catch (_) {}
      await Future<void>.delayed(MeshBleConfig.scanRestartInterval);
    }
  }

  Future<void> _onScanResults(List<ScanResult> results) async {
    if (!_up || _handlingScan) return;
    _handlingScan = true;
    try {
      final sorted = List<ScanResult>.from(results)
        ..sort((a, b) => b.rssi.compareTo(a.rssi));

      for (final r in sorted) {
        if (_devices.length >= maxPeers) break;
        if (r.rssi < MeshBleConfig.minConnectRssi) continue;
        final id = r.device.remoteId.str;
        if (_devices.containsKey(id) || _connecting.contains(id)) continue;

        _connecting.add(id);
        try {
          await r.device.connect(
            timeout: MeshBleConfig.connectTimeout,
            autoConnect: false,
          );
          try {
            await r.device.requestConnectionPriority(
              connectionPriorityRequest: ConnectionPriority.high,
            );
          } catch (_) {}
          try {
            await r.device.requestMtu(MeshBleConfig.preferredMtu);
          } catch (_) {}

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
        } finally {
          _connecting.remove(id);
        }
      }
    } finally {
      _handlingScan = false;
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
    _connecting.clear();
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
