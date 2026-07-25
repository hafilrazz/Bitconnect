import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../identity_store.dart';
import '../mesh_controller.dart';

class InternetDmScreen extends StatefulWidget {
  const InternetDmScreen({super.key, required this.controller});

  final MeshController controller;

  @override
  State<InternetDmScreen> createState() => _InternetDmScreenState();
}

class _InternetDmScreenState extends State<InternetDmScreen> {
  final _text = TextEditingController();
  final _peerId = TextEditingController();
  final _peerName = TextEditingController();

  MeshController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    if (c.activePeerId != null) {
      _peerId.text = c.activePeerId!;
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _text.dispose();
    _peerId.dispose();
    _peerName.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (c.internetOn) {
        await c.stopInternet();
      } else {
        await c.startInternet();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addContact() async {
    try {
      final name = _peerName.text.trim().isEmpty ? 'friend' : _peerName.text.trim();
      await c.addContact(Contact(name: name, netlessId: _peerId.text.trim()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact saved — messages are E2E encrypted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    try {
      if (!c.internetOn) await c.startInternet();
      await c.sendInternetDm(t);
      _text.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = c.messagesForActivePeer();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Internet E2E DM'),
        actions: [
          IconButton(
            tooltip: c.internetOn ? 'Disconnect' : 'Connect relays',
            onPressed: _toggle,
            icon: Icon(c.internetOn ? Icons.cloud_done : Icons.cloud_off),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    c.internetOn
                        ? '🔒 Pure E2E · relays see ciphertext only'
                        : 'Connect to send DMs worldwide (needs internet)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'Your Netless ID:\n${c.netlessId}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: c.netlessId));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Netless ID copied')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy my ID'),
                    ),
                  ),
                  if (c.internetStatus != null)
                    Text(
                      c.internetStatus!,
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              children: [
                TextField(
                  controller: _peerName,
                  decoration: const InputDecoration(
                    labelText: 'Contact name',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _peerId,
                  decoration: const InputDecoration(
                    labelText: 'Their Netless ID (64 hex)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.tonal(
                      onPressed: _addContact,
                      child: const Text('Save & chat'),
                    ),
                    const SizedBox(width: 8),
                    if (c.contacts.isNotEmpty)
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: c.activePeerId != null &&
                                  c.contacts
                                      .any((x) => x.netlessId == c.activePeerId)
                              ? c.activePeerId
                              : null,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            labelText: 'Contacts',
                          ),
                          items: c.contacts
                              .map(
                                (x) => DropdownMenuItem(
                                  value: x.netlessId,
                                  child: Text(
                                      '${x.name} (${x.netlessId.substring(0, 8)}…)'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              c.setActivePeer(v);
                              _peerId.text = v;
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: msgs.isEmpty
                ? const Center(
                    child: Text(
                      'No E2E messages yet.\nExchange Netless IDs with someone abroad,\nthen send — content is encrypted on-device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final m = msgs[i];
                      return Align(
                        alignment: m.isLocal
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.8,
                          ),
                          decoration: BoxDecoration(
                            color: m.isLocal
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🔒 ${m.nickname} · ${m.senderSignFingerprint}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
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
                        hintText: 'E2E message (internet)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.lock),
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
