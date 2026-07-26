import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import 'mesh_ble_config.dart';

/// Full dual-role BLE transport for Android:
/// - Peripheral: native GATT server + high-TX advertise (MethodChannel)
/// - Central: aggressive scan/connect ordered by RSSI for range + reliability
class AndroidBleMeshTransport implements MeshTransport {
  AndroidBleMeshTransport({
    this.serviceUuid = MeshConstants.serviceUuid,
    this.characteristicUuid = MeshConstants.characteristicUuid,
    this.maxPeers = MeshBleConfig.maxPeers,
  });

  static const _methods = MethodChannel('app.netless/ble_mesh');
  static const _events = EventChannel('app.netless/ble_mesh_events');

  final String serviceUuid;
  final String characteristicUuid;
  final int maxPeers;

  final _inbound = StreamController<MeshInbound>.broadcast();
  final Map<String, BluetoothDevice> _centrals = {};
  final Map<String, BluetoothCharacteristic> _remoteChars = {};
  final Set<String> _serverPeers = {};
  final Set<String> _connecting = {};

  StreamSubscription<dynamic>? _eventSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _up = false;
  bool _handlingScan = false;

  Guid get _svcGuid => Guid(serviceUuid);
  Guid get _chrGuid => Guid(characteristicUuid);

  @override
  List<String> get peerIds {
    final ids = <String>{..._serverPeers, ..._remoteChars.keys};
    return ids.toList();
  }

  @override
  Stream<MeshInbound> get inbound => _inbound.stream;

  @override
  Future<void> start() async {
    if (_up) return;
    if (kIsWeb || !Platform.isAndroid) {
      throw StateError('AndroidBleMeshTransport is Android-only');
    }

    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      throw StateError('Bluetooth LE not supported');
    }

    final state = await FlutterBluePlus.adapterState
        .where((s) =>
            s == BluetoothAdapterState.on ||
            s == BluetoothAdapterState.off ||
            s == BluetoothAdapterState.unauthorized)
        .first
        .timeout(const Duration(seconds: 8));
    if (state != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 20));
    }

    final ok = await _methods.invokeMethod<bool>('startPeripheral') ?? false;
    if (!ok) {
      throw StateError(
          'Failed to start BLE peripheral (enable Bluetooth & permissions)');
    }

    _eventSub = _events.receiveBroadcastStream().listen(_onNativeEvent);

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
        androidUsesFineLocation: false,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (_) {
      // Retry without service filter if OEM scan filter is flaky at distance.
      try {
        await FlutterBluePlus.startScan(
          timeout: MeshBleConfig.scanWindow,
          continuousUpdates: true,
          androidUsesFineLocation: false,
          androidScanMode: AndroidScanMode.lowLatency,
        );
      } catch (_) {}
    }
  }

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'];
    if (type == 'packet') {
      final from = event['from'] as String? ?? 'unknown';
      final data = event['data'];
      Uint8List bytes;
      if (data is Uint8List) {
        bytes = data;
      } else if (data is List) {
        bytes = Uint8List.fromList(data.cast<int>());
      } else {
        return;
      }
      if (bytes.isEmpty) return;
      _inbound.add(MeshInbound(fromPeerId: from, bytes: bytes));
    } else if (type == 'peers') {
      final peers = (event['peers'] as List?)?.cast<String>() ?? const [];
      _serverPeers
        ..clear()
        ..addAll(peers);
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
      // Strongest first for reliable links; still accept weak edge peers for multi-hop.
      final sorted = List<ScanResult>.from(results)
        ..sort((a, b) => b.rssi.compareTo(a.rssi));

      for (final r in sorted) {
        if (_remoteChars.length >= maxPeers) break;
        if (r.rssi < MeshBleConfig.minConnectRssi) continue;

        final id = r.device.remoteId.str;
        if (_remoteChars.containsKey(id) ||
            _centrals.containsKey(id) ||
            _connecting.contains(id)) {
          continue;
        }

        // If scanning without filter, only connect to our service UUID ads.
        final hasService = r.advertisementData.serviceUuids
            .any((u) => u == _svcGuid || u.str128 == _svcGuid.str128);
        if (!hasService && r.advertisementData.serviceUuids.isNotEmpty) {
          continue;
        }

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
          if (target == null) {
            await r.device.disconnect();
            continue;
          }
          if (target.properties.notify) {
            await target.setNotifyValue(true);
            target.onValueReceived.listen((value) {
              if (value.isEmpty) return;
              _inbound.add(MeshInbound(
                fromPeerId: id,
                bytes: Uint8List.fromList(value),
              ));
            });
          }
          _centrals[id] = r.device;
          _remoteChars[id] = target;
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
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    for (final d in _centrals.values) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
    _centrals.clear();
    _remoteChars.clear();
    _serverPeers.clear();
    _connecting.clear();
    try {
      await _methods.invokeMethod<void>('stopPeripheral');
    } catch (_) {}
  }

  @override
  Future<void> send(Uint8List data,
      {String? peerId, String? excludePeerId}) async {
    final remoteEntries = _remoteChars.entries.where((e) {
      if (peerId != null) return e.key == peerId;
      if (excludePeerId != null) return e.key != excludePeerId;
      return true;
    });
    for (final e in remoteEntries) {
      try {
        final c = e.value;
        final withoutResp = c.properties.writeWithoutResponse;
        await c.write(data,
            withoutResponse: withoutResp, allowLongWrite: false);
      } catch (_) {}
    }

    if (peerId == null) {
      try {
        await _methods.invokeMethod<void>('notifyCentrals', {'data': data});
      } catch (_) {}
    }
  }
}
