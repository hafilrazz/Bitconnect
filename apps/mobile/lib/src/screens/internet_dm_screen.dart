import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../identity_store.dart';
import '../mesh_controller.dart';
import '../widgets/composer_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/status_chip.dart';

class InternetDmScreen extends StatefulWidget {
  const InternetDmScreen({
    super.key,
    required this.controller,
    this.embedded = false,
  });

  final MeshController controller;
  final bool embedded;

  @override
  State<InternetDmScreen> createState() => _InternetDmScreenState();
}

class _InternetDmScreenState extends State<InternetDmScreen> {
  final _text = TextEditingController();
  final _peerId = TextEditingController();
  final _peerName = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  bool _showAddContact = true;

  MeshController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    if (c.activePeerId != null) {
      _peerId.text = c.activePeerId!;
      _showAddContact = c.contacts.isEmpty;
    }
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
    _peerId.dispose();
    _peerName.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (c.internetOn) {
        await c.stopInternet();
      } else {
        await c.startInternet();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addContact() async {
    try {
      final name =
          _peerName.text.trim().isEmpty ? 'friend' : _peerName.text.trim();
      await c.addContact(Contact(name: name, netlessId: _peerId.text.trim()));
      setState(() => _showAddContact = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact saved — messages stay E2E encrypted'),
        ),
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
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String? get _activeName {
    final id = c.activePeerId;
    if (id == null) return null;
    for (final x in c.contacts) {
      if (x.netlessId == id) return x.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msgs = c.messagesForActivePeer();
    final peerLabel = _activeName != null
        ? '$_activeName'
        : (c.activePeerId != null
            ? '${c.activePeerId!.substring(0, 8)}…'
            : 'No contact');

    final body = Column(
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Private 1:1 · pure end-to-end encryption',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Works India ↔ USA when both have internet. '
                  'Relays only see ciphertext.',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusChip(
                      label: c.internetOn ? 'Relays connected' : 'Offline',
                      active: c.internetOn,
                    ),
                    StatusChip(
                      label: 'Chatting: $peerLabel',
                      active: c.activePeerId != null,
                      activeColor: theme.colorScheme.tertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: c.netlessId));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Your Bitconnect ID copied')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy my ID'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _toggle,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(c.internetOn ? Icons.cloud_done : Icons.cloud),
                      label: Text(c.internetOn ? 'Connected' : 'Connect'),
                    ),
                  ],
                ),
                if (c.internetStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    c.internetStatus!,
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Contact picker / add
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            children: [
              if (c.contacts.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey(c.activePeerId),
                  initialValue: c.activePeerId != null &&
                          c.contacts.any((x) => x.netlessId == c.activePeerId)
                      ? c.activePeerId
                      : null,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Chat with',
                  ),
                  items: c.contacts
                      .map(
                        (x) => DropdownMenuItem(
                          value: x.netlessId,
                          child: Text(
                              '${x.name}  (${x.netlessId.substring(0, 8)}…)'),
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
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _showAddContact = !_showAddContact),
                  icon: Icon(_showAddContact ? Icons.expand_less : Icons.person_add),
                  label: Text(_showAddContact ? 'Hide add contact' : 'Add contact'),
                ),
              ),
              if (_showAddContact) ...[
                TextField(
                  controller: _peerName,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Alex in NYC',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _peerId,
                  decoration: const InputDecoration(
                    labelText: 'Their Bitconnect ID',
                    helperText: '64 hex characters — paste from their “Copy my ID”',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _addContact,
                    child: const Text('Save & chat'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 12),
        Expanded(
          child: msgs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 48, color: Colors.white38),
                        const SizedBox(height: 12),
                        Text(
                          c.activePeerId == null
                              ? 'Add a contact to start'
                              : 'No messages yet',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '1. Copy your ID and send it to a friend\n'
                          '2. Paste theirs under Add contact\n'
                          '3. Connect, then send a locked message',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    return MessageBubble(
                      isLocal: m.isLocal,
                      locked: true,
                      header: '${m.nickname} · ${m.senderSignFingerprint}',
                      body: m.text,
                      timeLabel: formatEpoch(m.timestamp),
                    );
                  },
                ),
        ),
        ComposerBar(
          controller: _text,
          onSend: _send,
          onAttach: _pickImage,
          enabled: c.activePeerId != null,
          hint: c.activePeerId == null
              ? 'Select a contact first'
              : 'Encrypted message',
          prefixIcon: Icons.lock_outline,
        ),
      ],
    );

    if (widget.embedded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Worldwide E2E'),
        ),
        body: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Worldwide E2E'),
        actions: [
          IconButton(
            tooltip: c.internetOn ? 'Disconnect' : 'Connect',
            onPressed: _busy ? null : _toggle,
            icon: Icon(c.internetOn ? Icons.cloud_done : Icons.cloud_off),
          ),
        ],
      ),
      body: body,
    );
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 95,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      await c.sendInternetMedia(Uint8List.fromList(bytes), name: file.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
