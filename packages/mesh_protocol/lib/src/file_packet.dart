import 'dart:convert';
import 'dart:typed_data';

/// Compact binary file envelope for mesh images.
///
/// ```
/// magic "BCF1" (4)
/// nameLen u8 | name utf8
/// mimeLen u8 | mime utf8
/// contentLen u32 BE | content
/// ```
class FilePacket {
  FilePacket({
    this.fileName,
    this.mimeType = 'image/jpeg',
    required this.content,
  });

  final String? fileName;
  final String mimeType;
  final Uint8List content;

  static const int maxPayloadBytes = 64 * 1024;
  static const int targetImageBytes = 12 * 1024;
  static const int maxImageDimension = 280;

  static final _magic = utf8.encode('BCF1');

  Uint8List encode() {
    if (content.length > maxPayloadBytes) {
      throw ArgumentError('content too large: ${content.length}');
    }
    final name = utf8.encode((fileName ?? 'photo.jpg').clampName(48));
    final mime = utf8.encode(mimeType.clampName(32));
    final b = BytesBuilder(copy: false);
    b.add(_magic);
    b.addByte(name.length);
    b.add(name);
    b.addByte(mime.length);
    b.add(mime);
    final n = content.length;
    b.addByte((n >> 24) & 0xff);
    b.addByte((n >> 16) & 0xff);
    b.addByte((n >> 8) & 0xff);
    b.addByte(n & 0xff);
    b.add(content);
    return b.toBytes();
  }

  static FilePacket? decode(Uint8List data) {
    if (data.length < 4 + 1 + 1 + 4) return null;
    if (data[0] != 0x42 || data[1] != 0x43 || data[2] != 0x46 || data[3] != 0x31) {
      return null; // not BCF1
    }
    var o = 4;
    final nameLen = data[o++];
    if (o + nameLen > data.length) return null;
    final name = utf8.decode(data.sublist(o, o + nameLen), allowMalformed: true);
    o += nameLen;
    if (o >= data.length) return null;
    final mimeLen = data[o++];
    if (o + mimeLen > data.length) return null;
    final mime = utf8.decode(data.sublist(o, o + mimeLen), allowMalformed: true);
    o += mimeLen;
    if (o + 4 > data.length) return null;
    final n = (data[o] << 24) | (data[o + 1] << 16) | (data[o + 2] << 8) | data[o + 3];
    o += 4;
    if (n < 0 || n > maxPayloadBytes || o + n > data.length) return null;
    final content = Uint8List.fromList(data.sublist(o, o + n));
    return FilePacket(fileName: name, mimeType: mime, content: content);
  }
}

extension on String {
  String clampName(int maxBytes) {
    var s = this;
    var b = utf8.encode(s);
    while (b.length > maxBytes && s.isNotEmpty) {
      s = s.substring(0, s.length - 1);
      b = utf8.encode(s);
    }
    return s;
  }
}

/// Mesh fragment of an encoded [FilePacket].
///
/// ```
/// "BCF2" (4) | transferId[8] | index u8 | total u8 | payload...
/// ```
/// Small header so BLE can carry more image bytes per hop.
class FileFragment {
  FileFragment({
    required this.transferId,
    required this.index,
    required this.total,
    required this.payload,
  });

  /// 8-byte transfer id (shorter = more room for image data).
  final Uint8List transferId;
  final int index;
  final int total;
  final Uint8List payload;

  static const int idLen = 8;
  /// Keep total mesh body well under MTU / long-write pain.
  static const int maxPayloadBytes = 350;

  static final _magic = utf8.encode('BCF2');

  Uint8List encode() {
    final b = BytesBuilder(copy: false);
    b.add(_magic);
    b.add(transferId);
    b.addByte(index & 0xff);
    b.addByte(total & 0xff);
    b.add(payload);
    return b.toBytes();
  }

  static FileFragment? decode(Uint8List data) {
    if (data.length < 4 + idLen + 2) return null;
    if (data[0] != 0x42 || data[1] != 0x43 || data[2] != 0x46 || data[3] != 0x32) {
      return null;
    }
    final transferId = Uint8List.fromList(data.sublist(4, 4 + idLen));
    final index = data[4 + idLen];
    final total = data[4 + idLen + 1];
    if (total == 0 || index >= total) return null;
    return FileFragment(
      transferId: transferId,
      index: index,
      total: total,
      payload: Uint8List.fromList(data.sublist(4 + idLen + 2)),
    );
  }

  static List<FileFragment> split(Uint8List transferId, Uint8List encodedFile) {
    assert(transferId.length == idLen);
    if (encodedFile.isEmpty) {
      return [
        FileFragment(
          transferId: transferId,
          index: 0,
          total: 1,
          payload: Uint8List(0),
        ),
      ];
    }
    final n = (encodedFile.length + maxPayloadBytes - 1) ~/ maxPayloadBytes;
    final out = <FileFragment>[];
    for (var i = 0; i < n; i++) {
      final start = i * maxPayloadBytes;
      final end = (start + maxPayloadBytes).clamp(0, encodedFile.length);
      out.add(FileFragment(
        transferId: transferId,
        index: i,
        total: n,
        payload: Uint8List.fromList(encodedFile.sublist(start, end)),
      ));
    }
    return out;
  }

  static String idHex(Uint8List id) =>
      id.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

class FileAssembler {
  final Map<String, _Pending> _pending = {};

  /// Returns full encoded [FilePacket] bytes when complete.
  Uint8List? add(FileFragment frag) {
    final key = FileFragment.idHex(frag.transferId);
    final p = _pending.putIfAbsent(key, () => _Pending(frag.total));
    if (frag.total != p.total) return null;
    if (frag.index >= p.total) return null;
    p.parts[frag.index] = frag.payload;
    p.received = DateTime.now();
    // drop stale
    _pending.removeWhere(
      (_, v) => DateTime.now().difference(v.received).inMinutes > 5,
    );
    if (p.parts.any((e) => e == null)) return null;
    final b = BytesBuilder(copy: false);
    for (final part in p.parts) {
      b.add(part!);
    }
    _pending.remove(key);
    return b.toBytes();
  }
}

class _Pending {
  _Pending(this.total)
      : parts = List<Uint8List?>.filled(total, null),
        received = DateTime.now();
  final int total;
  final List<Uint8List?> parts;
  DateTime received;
}
