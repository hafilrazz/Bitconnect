# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:/netless")

def w(rel, content):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content.replace("\r\n", "\n"), encoding="utf-8")
    print("wrote", rel)

w("apps/mobile/pubspec.yaml", """name: netless
description: Offline Bluetooth mesh chat.
publish_to: none
version: 0.1.0+1

environment:
  sdk: ">=3.3.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^2.6.1
  flutter_secure_storage: ^9.2.2
  shared_preferences: ^2.3.3
  mesh_protocol:
    path: ../../packages/mesh_protocol
  mesh_transport:
    path: ../../packages/mesh_transport
  mesh_ble:
    path: ../../packages/mesh_ble
  permission_handler: ^11.3.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
""")

w("apps/mobile/analysis_options.yaml", """include: package:flutter_lints/flutter.yaml
""")

w("apps/mobile/lib/main.dart", """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: NetlessApp()));
}
""")

w("apps/mobile/lib/src/app.dart", """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'screens/chat_screen.dart';
import 'screens/onboarding_screen.dart';

class NetlessApp extends ConsumerWidget {
  const NetlessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(identityReadyProvider);
    return MaterialApp(
      title: 'Netless',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6E4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: ready.when(
        data: (hasNick) =>
            hasNick ? const ChatScreen() : const OnboardingScreen(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          body: Center(child: Text('Startup error: $e')),
        ),
      ),
    );
  }
}
""")

w("apps/mobile/lib/src/identity_store.dart", """import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdentityStore {
  IdentityStore({
    FlutterSecureStorage? secure,
  }) : _secure = secure ?? const FlutterSecureStorage();

  static const _seedKey = 'netless_ed25519_seed_b64';
  static const _nickKey = 'netless_nickname';

  final FlutterSecureStorage _secure;

  Future<CryptoIdentity> loadOrCreateIdentity() async {
    final existing = await _secure.read(key: _seedKey);
    if (existing != null && existing.isNotEmpty) {
      final seed = base64Decode(existing);
      return CryptoIdentity.fromSeed(seed);
    }
    final id = await CryptoIdentity.generate();
    final seed = await id.exportSeed();
    await _secure.write(key: _seedKey, value: base64Encode(seed));
    return id;
  }

  Future<String?> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nickKey);
  }

  Future<void> setNickname(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nickKey, nickname.trim());
  }
}
""")

w("apps/mobile/lib/src/mesh_controller.dart", """import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mesh_ble/mesh_ble.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:mesh_transport/mesh_transport.dart';

enum TransportMode { fake, ble }

/// Owns MeshNode lifecycle and message list for the UI.
class MeshController extends ChangeNotifier {
  MeshController({
    required this.identity,
    required this.nickname,
    this.mode = TransportMode.fake,
  });

  final CryptoIdentity identity;
  String nickname;
  TransportMode mode;

  MeshNode? _node;
  MeshTransport? _transport;
  final List<ChatMessage> messages = [];
  StreamSubscription<ChatMessage>? _msgSub;
  bool meshOn = false;
  String? lastError;
  int peerCount = 0;
  Timer? _peerTimer;

  // Simulated multi-node for in-app demo (fake mode only)
  SimFabric? _sim;
  final List<MeshNode> _simRelays = [];

  Future<void> startMesh() async {
    lastError = null;
    try {
      await stopMesh();
      if (mode == TransportMode.ble) {
        final ok = await ensureBlePermissions();
        if (!ok) {
          throw StateError('Bluetooth permissions not granted');
        }
        _transport = BleMeshTransport();
      } else {
        _sim = SimFabric();
        final local = _sim!.create('local');
        // Relay path: local -- r1 -- r2 (for multi-hop demo inject)
        final r1 = _sim!.create('relay1');
        final r2 = _sim!.create('relay2');
        _sim!.link('local', 'relay1');
        _sim!.link('relay1', 'relay2');
        _transport = local;

        // Silent relay nodes so hop demos work when injecting at r2 later
        final id1 = await CryptoIdentity.generate();
        final id2 = await CryptoIdentity.generate();
        final n1 = MeshNode(identity: id1, transport: r1, nickname: 'relay1');
        final n2 = MeshNode(identity: id2, transport: r2, nickname: 'relay2');
        await n1.start();
        await n2.start();
        _simRelays.addAll([n1, n2]);
      }

      _node = MeshNode(
        identity: identity,
        transport: _transport!,
        nickname: nickname,
      );
      _msgSub = _node!.messages.listen((m) {
        messages.add(m);
        notifyListeners();
      });
      await _node!.start();
      meshOn = true;
      _peerTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final n = _transport?.peerIds.length ?? 0;
        if (n != peerCount) {
          peerCount = n;
          notifyListeners();
        }
      });
      peerCount = _transport?.peerIds.length ?? 0;
      notifyListeners();
    } catch (e) {
      lastError = e.toString();
      meshOn = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopMesh() async {
    _peerTimer?.cancel();
    _peerTimer = null;
    await _msgSub?.cancel();
    _msgSub = null;
    await _node?.dispose();
    _node = null;
    for (final r in _simRelays) {
      await r.dispose();
    }
    _simRelays.clear();
    _sim = null;
    if (_transport is FakeTransport) {
      await (_transport as FakeTransport).dispose();
    } else {
      await _transport?.stop();
    }
    _transport = null;
    meshOn = false;
    peerCount = 0;
    notifyListeners();
  }

  Future<void> send(String text) async {
    final node = _node;
    if (node == null || !meshOn) {
      throw StateError('Mesh is off');
    }
    node.nickname = nickname;
    await node.sendChat(text);
  }

  /// Inject a remote chat via sim relay2 -> relay1 -> local (fake multi-hop).
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
  }

  @override
  void dispose() {
    unawaited(stopMesh());
    super.dispose();
  }
}
""")

w("apps/mobile/lib/src/providers.dart", """import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import 'identity_store.dart';
import 'mesh_controller.dart';

final identityStoreProvider = Provider((ref) => IdentityStore());

final identityProvider = FutureProvider<CryptoIdentity>((ref) async {
  return ref.watch(identityStoreProvider).loadOrCreateIdentity();
});

final nicknameProvider = FutureProvider<String?>((ref) async {
  return ref.watch(identityStoreProvider).getNickname();
});

/// true if nickname already set
final identityReadyProvider = FutureProvider<bool>((ref) async {
  await ref.watch(identityProvider.future);
  final nick = await ref.watch(nicknameProvider.future);
  return nick != null && nick.isNotEmpty;
});

final meshControllerProvider =
    ChangeNotifierProvider<MeshController?>((ref) {
  // Created after onboarding via override / manual; see bootstrap.
  return null;
});

final meshControllerBootstrapProvider =
    FutureProvider<MeshController>((ref) async {
  final id = await ref.watch(identityProvider.future);
  final nick =
      await ref.watch(identityStoreProvider).getNickname() ?? 'anon';
  final mode = TransportMode.fake; // default safe; toggle in UI to BLE
  final c = MeshController(identity: id, nickname: nick, mode: mode);
  ref.onDispose(c.dispose);
  return c;
});
""")

w("apps/mobile/lib/src/screens/onboarding_screen.dart", """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'chat_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final nick = _controller.text.trim();
    if (nick.isEmpty) return;
    setState(() => _busy = true);
    final store = ref.read(identityStoreProvider);
    await store.setNickname(nick);
    await store.loadOrCreateIdentity();
    if (!mounted) return;
    ref.invalidate(nicknameProvider);
    ref.invalidate(identityReadyProvider);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idAsync = ref.watch(identityProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Text('Netless',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 8),
              Text(
                'Offline mesh chat over Bluetooth. No internet, no accounts.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              const SizedBox(height: 32),
              idAsync.when(
                data: (id) => Text(
                  'Your fingerprint: ${id.shortFingerprint}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  border: OutlineInputBorder(),
                  hintText: 'How you appear on #local',
                ),
                onSubmitted: (_) => _continue(),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _continue,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enter #local'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
""")

w("apps/mobile/lib/src/screens/chat_screen.dart", """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mesh_controller.dart';
import '../providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  MeshController? _controller;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _ensureController() async {
    if (_controller != null) return;
    _controller = await ref.read(meshControllerBootstrapProvider.future);
    _controller!.addListener(() {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureController());
  }

  Future<void> _toggleMesh() async {
    final c = _controller;
    if (c == null) return;
    try {
      if (c.meshOn) {
        await c.stopMesh();
      } else {
        await c.startMesh();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    final c = _controller;
    if (c == null) return;
    try {
      if (!c.meshOn) await c.startMesh();
      await c.send(t);
      _text.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final idAsync = ref.watch(identityProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('#local'),
        actions: [
          if (c != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  c.meshOn ? 'peers ${c.peerCount}' : 'mesh off',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          if (c != null)
            IconButton(
              tooltip: c.meshOn ? 'Stop mesh' : 'Start mesh',
              onPressed: _toggleMesh,
              icon: Icon(c.meshOn ? Icons.wifi_tethering : Icons.wifi_tethering_off),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (c == null) return;
              if (v == 'fake' || v == 'ble') {
                final wasOn = c.meshOn;
                if (wasOn) await c.stopMesh();
                c.mode =
                    v == 'ble' ? TransportMode.ble : TransportMode.fake;
                setState(() {});
                if (wasOn) await c.startMesh();
              } else if (v == 'inject') {
                await c.injectSimulatedRemote(
                  'Hello via multi-hop sim',
                  nick: 'sim-peer',
                );
              } else if (v == 'clear') {
                c.messages.clear();
                setState(() {});
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'fake',
                checked: c?.mode == TransportMode.fake,
                child: const Text('Transport: Fake (sim)'),
              ),
              CheckedPopupMenuItem(
                value: 'ble',
                checked: c?.mode == TransportMode.ble,
                child: const Text('Transport: BLE'),
              ),
              const PopupMenuItem(
                value: 'inject',
                child: Text('Inject simulated remote'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear messages'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              title: idAsync.when(
                data: (id) => Text(
                  '${c?.nickname ?? '...'} · ${id.shortFingerprint}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                loading: () => const Text('…'),
                error: (e, _) => Text('$e'),
              ),
              subtitle: Text(
                c?.mode == TransportMode.ble
                    ? 'BLE mode — needs physical phones'
                    : 'Sim mode — local + relays (no radio)',
              ),
            ),
          ),
          if (c?.lastError != null)
            Material(
              color: Colors.red.shade900,
              child: ListTile(
                dense: true,
                title: Text(c!.lastError!, style: const TextStyle(fontSize: 12)),
              ),
            ),
          Expanded(
            child: c == null
                ? const Center(child: CircularProgressIndicator())
                : c.messages.isEmpty
                    ? Center(
                        child: Text(
                          c.meshOn
                              ? 'Mesh on. Say hi on #local.'
                              : 'Turn mesh on to chat.',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: c.messages.length,
                        itemBuilder: (context, i) {
                          final m = c.messages[i];
                          return Align(
                            alignment: m.isLocal
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.8,
                              ),
                              decoration: BoxDecoration(
                                color: m.isLocal
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${m.nickname} · ${m.fingerprint}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(m.text),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(
                        hintText: 'Message #local',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
""")

w("apps/mobile/test/widget_smoke_test.dart", """import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

void main() {
  test('channel local id is 1', () {
    expect(Channels.local, 1);
    expect(Channels.idForName('#local'), 1);
  });
}
""")

# Android minimal manifests
w("apps/mobile/android/app/src/main/AndroidManifest.xml", """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"/>
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true"/>
    <application
        android:label="Netless"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
""")

w("LICENSE", """MIT License

Copyright (c) 2026 Netless contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
""")

print("app ok")
