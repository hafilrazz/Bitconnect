import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('FilePacket BCF1 roundtrip', () {
    final content = Uint8List.fromList(List<int>.generate(800, (i) => i % 256));
    final p = FilePacket(
      fileName: 'img_test.jpg',
      mimeType: 'image/jpeg',
      content: content,
    );
    final encoded = p.encode();
    final decoded = FilePacket.decode(encoded)!;
    expect(decoded.fileName, 'img_test.jpg');
    expect(decoded.mimeType, 'image/jpeg');
    expect(decoded.content, content);
  });

  test('FileFragment BCF2 split/assemble', () {
    final raw = Uint8List.fromList(List<int>.generate(2000, (i) => i % 251));
    final id = Uint8List.fromList(List<int>.generate(8, (i) => i + 1));
    final frags = FileFragment.split(id, raw);
    expect(frags.length, greaterThan(1));
    final asm = FileAssembler();
    Uint8List? done;
    for (final f in frags) {
      final wire = FileFragment.decode(f.encode())!;
      done = asm.add(wire);
    }
    expect(done, raw);
  });

  test('full file send assemble path', () {
    final jpeg = Uint8List.fromList(List<int>.generate(3000, (i) => (i * 7) % 256));
    final file = FilePacket(
      fileName: 'p.jpg',
      mimeType: 'image/jpeg',
      content: jpeg,
    );
    final encoded = file.encode();
    final id = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final frags = FileFragment.split(id, encoded);
    final asm = FileAssembler();
    Uint8List? blob;
    for (final f in frags) {
      blob = asm.add(f);
    }
    final out = FilePacket.decode(blob!)!;
    expect(out.content, jpeg);
    expect(out.fileName, 'p.jpg');
  });
}
