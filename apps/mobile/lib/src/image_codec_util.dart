import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mesh_protocol/mesh_protocol.dart';

/// Compress for mesh: small enough for multi-hop BLE reliability.
Uint8List compressForMesh(
  Uint8List input, {
  int maxSide = FilePacket.maxImageDimension,
  int quality = 70,
  int maxBytes = FilePacket.targetImageBytes,
}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    if (input.length <= maxBytes) return input;
    throw StateError('Could not decode image');
  }

  img.Image current = decoded;
  if (current.width > maxSide || current.height > maxSide) {
    current = current.width >= current.height
        ? img.copyResize(current, width: maxSide)
        : img.copyResize(current, height: maxSide);
  }

  // Flatten onto white (no alpha)
  final flat = img.Image(width: current.width, height: current.height);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, current);
  current = flat;

  var q = quality;
  var out = Uint8List.fromList(img.encodeJpg(current, quality: q));
  while (out.length > maxBytes && q > 25) {
    q -= 8;
    out = Uint8List.fromList(img.encodeJpg(current, quality: q));
  }

  var side = maxSide;
  while (out.length > maxBytes && side > 120) {
    side = (side * 0.8).round();
    current = current.width >= current.height
        ? img.copyResize(current, width: side)
        : img.copyResize(current, height: side);
    out = Uint8List.fromList(img.encodeJpg(current, quality: q.clamp(25, 70)));
  }

  if (out.length > FilePacket.maxPayloadBytes) {
    throw StateError('Image still too large (${out.length} B)');
  }
  return out;
}
