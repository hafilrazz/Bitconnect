import 'package:flutter/material.dart';
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
