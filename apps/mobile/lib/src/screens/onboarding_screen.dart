import 'package:flutter/material.dart';
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
