import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme/app_theme.dart';
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
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.xl,
              vertical: AppTheme.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppTheme.lg),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(AppTheme.lg),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.card,
                      border: Border.all(
                        color: AppTheme.brandGreen.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.brandGreen.withValues(alpha: 0.16),
                          blurRadius: 40,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/branding/app_logo.png',
                      width: 88,
                      height: 88,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.xl),
                Text(
                  'Bitconnect',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppTheme.sm),
                Text(
                  'Chat without accounts. Nearby mesh over Bluetooth, or '
                  'worldwide private DMs with end-to-end encryption.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppTheme.xl),
                const _FeatureCard(
                  icon: Icons.wifi_tethering,
                  iconColor: AppTheme.brandGreen,
                  title: 'Local mesh',
                  body:
                      'Nearby phones relay messages over BLE — no internet needed.',
                ),
                const SizedBox(height: AppTheme.md),
                const _FeatureCard(
                  icon: Icons.lock,
                  iconColor: AppTheme.accentBlue,
                  title: 'Worldwide E2E',
                  body:
                      'Private 1:1 messages across countries. Relays never see plaintext.',
                ),
                const SizedBox(height: AppTheme.xl),
                idAsync.when(
                  data: (id) => Container(
                    padding: const EdgeInsets.all(AppTheme.md),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      color: AppTheme.card.withValues(alpha: 0.7),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.fingerprint,
                          size: 18,
                          color: AppTheme.brandGreen,
                        ),
                        const SizedBox(width: AppTheme.sm),
                        Expanded(
                          child: Text(
                            'Signing fingerprint: ${id.shortFingerprint}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                ),
                const SizedBox(height: AppTheme.lg),
                TextField(
                  controller: _controller,
                  maxLength: 24,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Nickname',
                    border: OutlineInputBorder(),
                    hintText: 'How friends see you',
                    helperText:
                        'Nicknames are not unique — fingerprints prove identity.',
                  ),
                  onSubmitted: (_) => _continue(),
                ),
                const SizedBox(height: AppTheme.lg),
                FilledButton(
                  onPressed: _busy ? null : _continue,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
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
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTheme.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        color: AppTheme.card.withValues(alpha: 0.7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              color: iconColor.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: AppTheme.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.62),
                    height: 1.35,
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
