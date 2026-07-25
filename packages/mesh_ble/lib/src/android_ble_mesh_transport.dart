import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

/// Full dual-role BLE transport for Android:
/// - Peripheral: native GATT server + advertise (MethodChannel)
/// - Central: flutter_blue_plus scan/connect/write to peer servers
class AndroidBleMeshTransport implements MeshTransport {
  AndroidBleMeshTransport({
    this.serviceUuid = MeshConstants.serviceUuid,
    this.characteristicUuid = MeshConstants.characteristicUuid,
    this.maxPeers = 6,
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

  StreamSubscription<dynamic>? _eventSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _up = false;

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

    // Wait for adapter on (user may need to enable BT).
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

    await FlutterBluePlus.startScan(
      withServices: [_svcGuid],
      timeout: const Duration(seconds: 5),
      continuousUpdates: true,
      androidUsesFineLocation: false,
    );
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
    unawaited(_scanLoop());
    _up = true;
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
          await FlutterBluePlus.startScan(
            withServices: [_svcGuid],
            timeout: const Duration(seconds: 5),
            androidUsesFineLocation: false,
          );
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  Future<void> _onScanResults(List<ScanResult> results) async {
    if (!_up) return;
    for (final r in results) {
      if (_remoteChars.length >= maxPeers) break;
      final id = r.device.remoteId.str;
      if (_remoteChars.containsKey(id) || _centrals.containsKey(id)) continue;
      // Skip connecting to self if address ever appears (rare).
      try {
        await r.device.connect(
          timeout: const Duration(seconds: 10),
          autoConnect: false,
        );
        await r.device.requestMtu(185);
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
      }
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
    try {
      await _methods.invokeMethod<void>('stopPeripheral');
    } catch (_) {}
  }

  @override
  Future<void> send(Uint8List data,
      {String? peerId, String? excludePeerId}) async {
    // 1) Write to remotes we are central to
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

    // 2) Notify centrals connected to our GATT server
    if (peerId == null) {
      try {
        await _methods.invokeMethod<void>('notifyCentrals', {'data': data});
      } catch (_) {}
    }
  }
}
