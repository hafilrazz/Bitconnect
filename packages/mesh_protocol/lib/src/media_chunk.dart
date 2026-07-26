import 'dart:convert';
import 'dart:typed_data';

// BytesBuilder

/// Multi-packet media transfer over the mesh (BLE-friendly chunk size).
class MediaChunk {
  MediaChunk({
    required this.mediaId,
    required this.index,
    required this.total,
    required this.mime,
    required this.filename,
    required this.data,
  });

  final String mediaId; // hex id shared across chunks
  final int index;
  final int total;
  final String mime;
  final String filename;
  final Uint8List data;

  /// Target max binary chunk size (leaves room for JSON + packet headers).
  static const int maxChunkPayloadBytes = 280;

  Map<String, dynamic> toJson() => {
        'k': 'c',
        'id': mediaId,
        'i': index,
        'n': total,
        'm': mime,
        'f': filename,
        'd': base64Encode(data),
      };

  String encode() => jsonEncode(toJson());

  static MediaChunk? tryParse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map) return null;
      if (j['k'] != 'c') return null;
      final b64 = j['d'] as String? ?? '';
      return MediaChunk(
        mediaId: j['id'] as String? ?? '',
        index: j['i'] as int? ?? 0,
        total: j['n'] as int? ?? 0,
        mime: j['m'] as String? ?? 'image/jpeg',
        filename: j['f'] as String? ?? 'file',
        data: Uint8List.fromList(base64Decode(b64)),
      );
    } catch (_) {
      return null;
    }
  }

  /// Split raw media bytes into mesh-safe chunks.
  static List<MediaChunk> split({
    required String mediaId,
    required String mime,
    required String filename,
    required Uint8List bytes,
    int payloadBytes = maxChunkPayloadBytes,
  }) {
    if (bytes.isEmpty) {
      return [
        MediaChunk(
          mediaId: mediaId,
          index: 0,
          total: 1,
          mime: mime,
          filename: filename,
          data: Uint8List(0),
        ),
      ];
    }
    final chunks = <MediaChunk>[];
    final total = (bytes.length + payloadBytes - 1) ~/ payloadBytes;
    for (var i = 0; i < total; i++) {
      final start = i * payloadBytes;
      final end = (start + payloadBytes > bytes.length)
          ? bytes.length
          : start + payloadBytes;
      chunks.add(MediaChunk(
        mediaId: mediaId,
        index: i,
        total: total,
        mime: mime,
        filename: filename,
        data: Uint8List.fromList(bytes.sublist(start, end)),
      ));
    }
    return chunks;
  }
}

/// Reassembles [MediaChunk]s keyed by mediaId.
class MediaAssembler {
  final Map<String, _Pending> _pending = {};

  /// Returns completed file bytes when all chunks arrived, else null.
  Uint8List? add(MediaChunk chunk) {
    if (chunk.mediaId.isEmpty || chunk.total <= 0) return null;
    final p = _pending.putIfAbsent(
      chunk.mediaId,
      () => _Pending(chunk.total, chunk.mime, chunk.filename),
    );
    if (chunk.index < 0 || chunk.index >= p.total) return null;
    p.parts[chunk.index] = chunk.data;
    p.mime = chunk.mime;
    p.filename = chunk.filename;
    if (p.parts.any((e) => e == null)) return null;
    final out = BytesBuilder(copy: false);
    for (final part in p.parts) {
      out.add(part!);
    }
    _pending.remove(chunk.mediaId);
    return out.toBytes();
  }

  String? filenameOf(String mediaId) => _pending[mediaId]?.filename;
  String? mimeOf(String mediaId) => _pending[mediaId]?.mime;
}

class _Pending {
  _Pending(this.total, this.mime, this.filename)
      : parts = List<Uint8List?>.filled(total, null);
  final int total;
  String mime;
  String filename;
  final List<Uint8List?> parts;
}
