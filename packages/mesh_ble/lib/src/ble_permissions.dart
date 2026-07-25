import 'dart:io';

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
