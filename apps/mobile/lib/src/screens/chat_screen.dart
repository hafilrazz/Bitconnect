import 'package:flutter/material.dart';

import '../mesh_controller.dart';
import '../widgets/message_bubble.dart';
import '../widgets/status_chip.dart';

/// Local BLE / sim mesh channel UI (`#local`).
class LocalMeshPage extends StatefulWidget {
  const LocalMeshPage({super.key, required this.controller});

  final MeshController controller;

  @override
  State<LocalMeshPage> createState() => _LocalMeshPageState();
}

class _LocalMeshPageState extends State<LocalMeshPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  MeshController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _toggleMesh() async {
    setState(() => _busy = true);
    try {
      if (c.meshOn) {
        await c.stopMesh();
      } else {
        await c.startMesh();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    try {
      if (!c.meshOn) await c.startMesh();
      await c.send(t);
      _text.clear();
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('#local'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'fake' || v == 'ble') {
                final wasOn = c.meshOn;
                if (wasOn) await c.stopMesh();
                c.mode = v == 'ble' ? TransportMode.ble : TransportMode.fake;
                setState(() {});
                if (wasOn) await c.startMesh();
              } else if (v == 'inject') {
                await c.injectSimulatedRemote('Hello via multi-hop sim',
                    nick: 'sim-peer');
              } else if (v == 'clear') {
                c.messages.clear();
                setState(() {});
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'ble',
                checked: c.mode == TransportMode.ble,
                child: const Text('Radio: Bluetooth'),
              ),
              CheckedPopupMenuItem(
                value: 'fake',
                checked: c.mode == TransportMode.fake,
                child: const Text('Radio: Simulator'),
              ),
              const PopupMenuItem(
                value: 'inject',
                child: Text('Inject simulated hop'),
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
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.nickname} · ${c.identity.shortFingerprint}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusChip(
                        label: c.meshOn
                            ? 'Mesh on · ${c.peerCount} peer${c.peerCount == 1 ? '' : 's'}'
                            : 'Mesh off',
                        active: c.meshOn,
                      ),
                      StatusChip(
                        label: c.mode == TransportMode.ble ? 'Bluetooth' : 'Simulator',
                        active: true,
                        activeColor: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.mode == TransportMode.ble
                        ? 'High-TX BLE + multi-hop mesh. Keep the app open; more phones extend range.'
                        : 'Simulator mode for demos without radios. Switch to Bluetooth in ⋮ menu.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
          if (c.lastError != null)
            Material(
              color: Colors.red.shade900,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline, size: 18),
                title: Text(c.lastError!, style: const TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    c.lastError = null;
                    setState(() {});
                  },
                ),
              ),
            ),
          Expanded(
            child: c.messages.isEmpty
                ? _EmptyLocal(meshOn: c.meshOn, onStart: _busy ? null : _toggleMesh)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: c.messages.length,
                    itemBuilder: (context, i) {
                      final m = c.messages[i];
                      return MessageBubble(
                        isLocal: m.isLocal,
                        header: '${m.nickname} · ${m.fingerprint}',
                        body: m.text,
                        timeLabel: formatEpoch(m.packet.timestamp),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: c.meshOn ? 'Stop mesh' : 'Start mesh',
                    onPressed: _busy ? null : _toggleMesh,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(c.meshOn
                            ? Icons.wifi_tethering
                            : Icons.wifi_tethering_off),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText: 'Message everyone on #local',
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

class _EmptyLocal extends StatelessWidget {
  const _EmptyLocal({required this.meshOn, required this.onStart});

  final bool meshOn;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              meshOn ? Icons.forum_outlined : Icons.wifi_tethering,
              size: 48,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            Text(
              meshOn ? 'Mesh is live' : 'Start the local mesh',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              meshOn
                  ? 'Say hi on #local. Anyone in radio range of the mesh can read this channel — it is not private.'
                  : 'Turn on mesh to discover nearby Bitconnect users and relay messages.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.35),
            ),
            if (!meshOn && onStart != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Start mesh'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kept for any old routes; prefer [HomeShell].
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Legacy entry — redirect users via home shell in app.dart
    return const Scaffold(
      body: Center(child: Text('Use HomeShell')),
    );
  }
}
