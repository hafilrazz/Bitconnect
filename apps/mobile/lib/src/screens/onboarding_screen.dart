import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'home_shell.dart';

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
    await store.loadOrCreate();
    if (!mounted) return;
    ref.invalidate(nicknameProvider);
    ref.invalidate(identityReadyProvider);
    ref.invalidate(appIdentityProvider);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idAsync = ref.watch(identityProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(Icons.hub_outlined, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Netless',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Chat without accounts. Local mesh over Bluetooth, or '
                'worldwide private DMs with end-to-end encryption.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              _FeatureCard(
                icon: Icons.wifi_tethering,
                title: 'Local mesh',
                body: 'Nearby phones relay messages over BLE — no internet needed.',
              ),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.lock,
                title: 'Worldwide E2E',
                body: 'Private 1:1 messages across countries. Relays never see plaintext.',
              ),
              const SizedBox(height: 28),
              idAsync.when(
                data: (id) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    'Signing fingerprint: ${id.shortFingerprint}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                maxLength: 24,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  border: OutlineInputBorder(),
                  hintText: 'How friends see you',
                  helperText: 'Nicknames are not unique — fingerprints prove identity.',
                ),
                onSubmitted: (_) => _continue(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _continue,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Get started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
