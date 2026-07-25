from pathlib import Path

# identity_store - remove unused import
p = Path(r"C:/netless/apps/mobile/lib/src/identity_store.dart")
t = p.read_text(encoding="utf-8")
t = t.replace("import 'dart:typed_data';\n\n", "")
p.write_text(t, encoding="utf-8")

# mesh_controller - clean injectSimulatedRemote
p = Path(r"C:/netless/apps/mobile/lib/src/mesh_controller.dart")
t = p.read_text(encoding="utf-8")
old = '''  /// Inject a remote chat via sim relay2 -> relay1 -> local (fake multi-hop).
  Future<void> injectSimulatedRemote(String text, {String nick = 'remote'}) async {
    if (mode != TransportMode.fake || _sim == null) return;
    final id = await CryptoIdentity.generate();
    final t = FakeTransport(echo: false);
    // Build signed packet and inject at edge peer relay2
    final edge = MeshNode(identity: id, transport: _sim!.nodes['relay2']!, nickname: nick);
    // temporarily: use node on relay2's transport — but relay2 already has a node.
    // Instead craft via a one-shot sender on a new leaf linked to relay2.
    final leaf = _sim!.create('leaf-${DateTime.now().microsecondsSinceEpoch}');
    _sim!.link(leaf.id, 'relay2');
    final sender = MeshNode(identity: id, transport: leaf, nickname: nick);
    await sender.start();
    await sender.sendChat(text);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sender.dispose();
  }'''
# The file may have different quotes - read and rewrite the method via lines
text = p.read_text(encoding="utf-8")
start = text.find("  /// Inject a remote chat")
end = text.find("  @override\n  void dispose()")
if start == -1 or end == -1:
    print("markers not found", start, end)
else:
    new_method = '''  /// Inject a remote chat via sim leaf -> relay2 -> relay1 -> local (multi-hop).
  Future<void> injectSimulatedRemote(String text, {String nick = 'remote'}) async {
    if (mode != TransportMode.fake || _sim == null) return;
    final id = await CryptoIdentity.generate();
    final leaf = _sim!.create('leaf-${DateTime.now().microsecondsSinceEpoch}');
    _sim!.link(leaf.id, 'relay2');
    final sender = MeshNode(identity: id, transport: leaf, nickname: nick);
    await sender.start();
    await sender.sendChat(text);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sender.dispose();
  }

'''
    # Fix string interpolation - in Python we need actual dart interpolation
    new_method = """  /// Inject a remote chat via sim leaf -> relay2 -> relay1 -> local (multi-hop).
  Future<void> injectSimulatedRemote(String text, {String nick = 'remote'}) async {
    if (mode != TransportMode.fake || _sim == null) return;
    final id = await CryptoIdentity.generate();
    final leaf =
        _sim!.create('leaf-${DateTime.now().microsecondsSinceEpoch}');
    _sim!.link(leaf.id, 'relay2');
    final sender = MeshNode(identity: id, transport: leaf, nickname: nick);
    await sender.start();
    await sender.sendChat(text);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sender.dispose();
  }

"""
    # Python will eat $ - use format carefully
    new_method = (
        "  /// Inject a remote chat via sim leaf -> relay2 -> relay1 -> local (multi-hop).\n"
        "  Future<void> injectSimulatedRemote(String text, {String nick = 'remote'}) async {\n"
        "    if (mode != TransportMode.fake || _sim == null) return;\n"
        "    final id = await CryptoIdentity.generate();\n"
        "    final leaf =\n"
        "        _sim!.create('leaf-${DateTime.now().microsecondsSinceEpoch}');\n"
        "    _sim!.link(leaf.id, 'relay2');\n"
        "    final sender = MeshNode(identity: id, transport: leaf, nickname: nick);\n"
        "    await sender.start();\n"
        "    await sender.sendChat(text);\n"
        "    await Future<void>.delayed(const Duration(milliseconds: 80));\n"
        "    await sender.dispose();\n"
        "  }\n\n"
    )
    p.write_text(text[:start] + new_method + text[end:], encoding="utf-8")
    print("mesh_controller patched")

print("done")
