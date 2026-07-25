import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

void main() {
  test('channel local id is 1', () {
    expect(Channels.local, 1);
    expect(Channels.idForName('#local'), 1);
  });
}
