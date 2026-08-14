import 'package:flutter/material.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import '../mesh_controller.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final MeshController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  MeshController get c => widget.controller;
  final _channelName = TextEditingController();
  final _joinKey = TextEditingController();

  @override
  void dispose() {
    _channelName.dispose();
    _joinKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings & channels')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            icon: Icons.battery_charging_full,
            title: 'Power mode',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<PowerMode>(
                  segments: const [
                    ButtonSegment(
                        value: PowerMode.performance, label: Text('Perf')),
                    ButtonSegment(
                        value: PowerMode.balanced, label: Text('Balanced')),
                    ButtonSegment(value: PowerMode.saver, label: Text('Saver')),
                  ],
                  selected: {c.powerMode},
                  onSelectionChanged: (s) {
                    c.setPowerMode(s.first);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Saver = LPN-like sparse ferry/scan. Perf = best mesh range.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          _Section(
            icon: Icons.chat_bubble_outline,
            title: 'Local channels',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: c.channelNames
                      .map(
                        (n) => ChoiceChip(
                          label: Text(n),
                          selected: c.activeChannelName == n,
                          onSelected: (_) {
                            c.setActiveChannel(n);
                            setState(() {});
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _channelName,
                  decoration: const InputDecoration(
                    labelText: 'New channel name',
                    hintText: 'events',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.tonal(
                      onPressed: () {
                        final n = _channelName.text.trim();
                        if (n.isEmpty) return;
                        c.addChannel(n);
                        setState(() {});
                      },
                      child: const Text('Add public'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final n = _channelName.text.trim();
                        if (n.isEmpty) return;
                        final key = c.createEncryptedChannel(n);
                        setState(() {});
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Group E2E key'),
                            content: SelectableText(
                              'Share this key out-of-band:\n\n$key',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Create E2E group'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _joinKey,
                  decoration: const InputDecoration(
                    labelText: 'Join with channel key (base64url)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () {
                    final n = _channelName.text.trim().isEmpty
                        ? 'group'
                        : _channelName.text.trim();
                    try {
                      c.joinEncryptedChannel(n, _joinKey.text.trim());
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Joined encrypted channel')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    }
                  },
                  child: const Text('Join encrypted channel'),
                ),
              ],
            ),
          ),
          _Section(
            icon: Icons.sync_alt,
            title: 'Reliability',
            child: Column(
              children: [
                _InfoTile(
                  title: 'Store-and-forward ferry',
                  subtitle:
                      'Queued packets: ${c.ferryQueued}\n'
                      'Messages are held and re-broadcast when peers reappear.',
                ),
                _InfoTile(
                  title: 'Protocol',
                  subtitle:
                      'v${MeshConstants.version} · max body ${MeshConstants.maxBodyBytes}B · '
                      'TTL ${MeshConstants.maxTtl} · rate limit '
                      '${MeshConstants.rateLimitMaxPackets}/'
                      '${MeshConstants.rateLimitWindowMs ~/ 1000}s',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        color: AppTheme.card.withValues(alpha: 0.7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.brandGreen),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
