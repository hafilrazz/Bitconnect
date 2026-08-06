import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mesh_protocol/mesh_protocol.dart';

const int localMeshImageMaxSide = 720;
const int localMeshImageQuality = 84;
const int localMeshImageTargetBytes = 56 * 1024;

const int internetImageMaxSide = 1024;
const int internetImageQuality = 86;
const int internetImageMaxBytes = 140 * 1024;

/// Compress for mesh: high enough quality to inspect, capped for BLE fragments.
Uint8List compressForMesh(Uint8List input) {
  final out = _compressJpeg(
    input,
    maxSide: localMeshImageMaxSide,
    quality: localMeshImageQuality,
    maxBytes: localMeshImageTargetBytes,
    minSide: 240,
    minQuality: 42,
  );
  if (out.length > FilePacket.maxPayloadBytes) {
    throw StateError('Image still too large (${out.length} B)');
  }
  return out;
}

/// Compress for worldwide E2E media. Internet relays can tolerate a larger
/// payload than BLE, while keeping encrypted DM size bounded.
Uint8List compressForInternetMedia(Uint8List input) {
  final out = _compressJpeg(
    input,
    maxSide: internetImageMaxSide,
    quality: internetImageQuality,
    maxBytes: internetImageMaxBytes,
    minSide: 360,
    minQuality: 48,
  );
  if (out.length > internetImageMaxBytes) {
    throw StateError('Image still too large (${out.length} B)');
  }
  return out;
}

Uint8List _compressJpeg(
  Uint8List input, {
  required int maxSide,
  required int quality,
  required int maxBytes,
  required int minSide,
  required int minQuality,
}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    if (input.length <= maxBytes) return input;
    throw StateError('Could not decode image');
  }

  img.Image current = decoded;

  if (current.width > maxSide || current.height > maxSide) {
    current = current.width >= current.height
        ? img.copyResize(current,
            width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(current,
            height: maxSide, interpolation: img.Interpolation.average);
  }

  final flat = img.Image(width: current.width, height: current.height);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, current);
  current = flat;

  var q = quality;
  var out = Uint8List.fromList(img.encodeJpg(current, quality: q));
  while (out.length > maxBytes && q > minQuality) {
    q -= 6;
    out = Uint8List.fromList(img.encodeJpg(current, quality: q));
  }

  var side = current.width >= current.height ? current.width : current.height;
  while (out.length > maxBytes && side > minSide) {
    side = (side * 0.86).round();
    current = current.width >= current.height
        ? img.copyResize(current,
            width: side, interpolation: img.Interpolation.average)
        : img.copyResize(current,
            height: side, interpolation: img.Interpolation.average);
    out = Uint8List.fromList(
      img.encodeJpg(current, quality: q.clamp(minQuality, quality)),
    );
  }

  return out;
}
