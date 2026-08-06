import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import '../mesh_controller.dart';
import '../widgets/composer_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/status_chip.dart';
import 'image_viewer_screen.dart';
import 'settings_screen.dart';

/// Local BLE / sim mesh channel UI.
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

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        // Compressor will cap the final JPEG for mesh delivery.
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 100,
      );
      if (file == null) return;
      if (!c.meshOn) await c.startMesh();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compressing and sending image over mesh…'),
        ),
      );
      await c.sendImageBytes(Uint8List.fromList(bytes), filename: file.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msgs = c.messagesForActiveChannel;
    final encrypted = c.channelKeyB64.containsKey(c.activeChannelId);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(child: Text(c.activeChannelName)),
            if (encrypted) ...[
              const SizedBox(width: 6),
              const Icon(Icons.lock, size: 16),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings / channels',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(controller: c),
                ),
              );
            },
            icon: const Icon(Icons.tune),
          ),
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
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.6,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.nickname,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.identity.shortFingerprint,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(
                        label: c.meshOn
                            ? 'Mesh on · ${c.peerCount} peer${c.peerCount == 1 ? '' : 's'}'
                            : 'Mesh off',
                        active: c.meshOn,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusChip(
                        label: c.mode == TransportMode.ble
                            ? 'Bluetooth'
                            : 'Simulator',
                        active: true,
                        activeColor: theme.colorScheme.primary,
                      ),
                      if (c.ferryQueued > 0)
                        StatusChip(
                          label: 'Ferry ${c.ferryQueued}',
                          active: true,
                          activeColor: Colors.orangeAccent,
                        ),
                      StatusChip(
                        label: c.powerMode.name,
                        active: c.powerMode == PowerMode.performance,
                        activeColor: Colors.amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: c.channelNames
                          .map(
                            (n) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(n,
                                    style: const TextStyle(fontSize: 12)),
                                selected: c.activeChannelName == n,
                                onSelected: (_) {
                                  c.setActiveChannel(n);
                                  setState(() {});
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
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
                title:
                    Text(c.lastError!, style: const TextStyle(fontSize: 12)),
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
            child: msgs.isEmpty
                ? _EmptyLocal(meshOn: c.meshOn, onStart: _busy ? null : _toggleMesh)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final m = msgs[i];
                      final img = m.mediaBytes ??
                          (m.mediaId != null
                              ? c.mediaGallery[m.mediaId!]
                              : null);
                      return GestureDetector(
                        onTap: () {
                          if (img != null && img.isNotEmpty) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ImageViewerScreen(
                                  bytes: img,
                                  title: m.text,
                                ),
                              ),
                            );
                            if (!m.isLocal && c.meshOn) c.markRead(m);
                            return;
                          }
                          if (!m.isLocal && c.meshOn) c.markRead(m);
                        },
                        child: MessageBubble(
                          isLocal: m.isLocal,
                          locked: encrypted ||
                              (m.packet.flags & MeshConstants.flagEncrypted) !=
                                  0,
                          header: '${m.nickname} · ${m.fingerprint}',
                          body: m.text,
                          timeLabel: formatEpoch(m.packet.timestamp),
                          status: m.isLocal
                              ? (c.delivery[m.msgIdHex] ?? m.status)
                              : null,
                          imageBytes: img,
                        ),
                      );
                    },
                  ),
          ),
          ComposerBar(
            controller: _text,
            onSend: _send,
            onAttach: _pickImage,
            onPrimaryAction: _toggleMesh,
            primaryBusy: _busy,
            primaryTooltip: c.meshOn ? 'Stop mesh' : 'Start mesh',
            primaryIcon: c.meshOn
                ? Icons.wifi_tethering
                : Icons.wifi_tethering_off,
            hint: encrypted
                ? 'Encrypted message on ${c.activeChannelName}'
                : 'Message ${c.activeChannelName}',
            prefixIcon: encrypted ? Icons.lock_outline : null,
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
                  ? 'Public channels are readable by the mesh. Use encrypted channels in Settings for group E2E.'
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
