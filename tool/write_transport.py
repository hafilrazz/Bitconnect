# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:/netless")

def w(rel, content):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content.replace("\r\n", "\n"), encoding="utf-8")
    print("wrote", rel)

w("packages/mesh_transport/pubspec.yaml", """name: mesh_transport
description: Transport interfaces helpers and FakeTransport for Netless.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  mesh_protocol:
    path: ../mesh_protocol
  meta: ^1.12.0

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
""")

w("packages/mesh_transport/analysis_options.yaml", """include: package:lints/recommended.yaml
""")

w("packages/mesh_transport/lib/mesh_transport.dart", """library mesh_transport;

export 'src/fake_transport.dart';
export 'src/sim_fabric.dart';
""")

w("packages/mesh_transport/lib/src/fake_transport.dart", """import 'dart:async';
import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';

/// Loopback transport: messages sent come back from a virtual peer.
/// Useful for single-device UI demos without BLE.
class FakeTransport implements MeshTransport {
  FakeTransport({this.loopbackPeerId = 'loopback', this.echo = false});

  final String loopbackPeerId;
  /// If true, sends are echoed back as inbound (for local UI testing).
  final bool echo;

  final _inbound = StreamController<MeshInbound>.broadcast();
  final _peers = <String>{};
  bool _up = false;

  void addVirtualPeer(String id) => _peers.add(id);
  void removeVirtualPeer(String id) => _peers.remove(id);

  @override
  List<String> get peerIds => _up ? _peers.toList() : <String>[];

  @override
  Stream<MeshInbound> get inbound => _inbound.stream;

  @override
  Future<void> start() async {
    _up = true;
    if (_peers.isEmpty) {
      _peers.add(loopbackPeerId);
    }
  }

  @override
  Future<void> stop() async {
    _up = false;
  }

  @override
  Future<void> send(Uint8List data,
      {String? peerId, String? excludePeerId}) async {
    if (!_up) return;
    if (echo) {
      scheduleMicrotask(() {
        _inbound.add(MeshInbound(fromPeerId: loopbackPeerId, bytes: data));
      });
    }
  }

  /// Inject a packet as if received from [fromPeerId].
  void inject(Uint8List bytes, {String fromPeerId = 'remote'}) {
    if (!_up) return;
    _inbound.add(MeshInbound(fromPeerId: fromPeerId, bytes: bytes));
  }

  Future<void> dispose() async {
    await stop();
    await _inbound.close();
  }
}
""")

w("packages/mesh_transport/lib/src/sim_fabric.dart", """import 'dart:async';
import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';

/// Multi-node in-process fabric for demos and tests.
class SimFabric {
  final Map<String, SimTransport> nodes = {};
  final Map<String, Set<String>> links = {};

  SimTransport create(String id) {
    final t = SimTransport(id, this);
    nodes[id] = t;
    links.putIfAbsent(id, () => {});
    return t;
  }

  void link(String a, String b) {
    links.putIfAbsent(a, () => {}).add(b);
    links.putIfAbsent(b, () => {}).add(a);
  }

  void unlink(String a, String b) {
    links[a]?.remove(b);
    links[b]?.remove(a);
  }
}

class SimTransport implements MeshTransport {
  SimTransport(this.id, this.fabric);

  final String id;
  final SimFabric fabric;
  final _inbound = StreamController<MeshInbound>.broadcast();
  bool _up = false;

  @override
  List<String> get peerIds =>
      _up ? (fabric.links[id]?.toList() ?? []) : <String>[];

  @override
  Stream<MeshInbound> get inbound => _inbound.stream;

  @override
  Future<void> start() async => _up = true;

  @override
  Future<void> stop() async => _up = false;

  @override
  Future<void> send(Uint8List data,
      {String? peerId, String? excludePeerId}) async {
    if (!_up) return;
    final targets = <String>[];
    if (peerId != null) {
      if (fabric.links[id]?.contains(peerId) == true) targets.add(peerId);
    } else {
      for (final p in fabric.links[id] ?? <String>{}) {
        if (p != excludePeerId) targets.add(p);
      }
    }
    for (final t in targets) {
      final other = fabric.nodes[t];
      if (other == null || !other._up) continue;
      scheduleMicrotask(() {
        other._inbound.add(MeshInbound(fromPeerId: id, bytes: data));
      });
    }
  }
}
""")

# mesh_ble package
w("packages/mesh_ble/pubspec.yaml", """name: mesh_ble
description: BLE transport for Netless using flutter_blue_plus.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.3.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: ^1.35.0
  mesh_protocol:
    path: ../mesh_protocol
  permission_handler: ^11.3.1

dev_dependencies:
  flutter_lints: ^5.0.0
  flutter_test:
    sdk: flutter
""")

w("packages/mesh_ble/analysis_options.yaml", """include: package:flutter_lints/flutter.yaml
""")

w("packages/mesh_ble/lib/mesh_ble.dart", """library mesh_ble;

export 'src/ble_mesh_transport.dart';
export 'src/ble_permissions.dart';
""")

w("packages/mesh_ble/lib/src/ble_permissions.dart", """import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Request runtime permissions required for BLE mesh scanning.
Future<bool> ensureBlePermissions() async {
  if (kIsWeb) return false;
  if (Platform.isAndroid) {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }
  if (Platform.isIOS) {
    final status = await Permission.bluetooth.request();
    return status.isGranted || status.isLimited;
  }
  return true;
}
""")

w("packages/mesh_ble/lib/src/ble_mesh_transport.dart", """import 'dart:async';
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
""")

print("transport+ble ok")
