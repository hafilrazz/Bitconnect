import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';

class BitconnectApp extends ConsumerWidget {
  const BitconnectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(identityReadyProvider);
    return MaterialApp(
      title: 'Bitconnect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: ready.when(
        data: (hasNick) =>
            hasNick ? const HomeShell() : const OnboardingScreen(),
        loading: () => const _SplashScreen(),
        error: (e, _) => Scaffold(
          body: Center(child: Text('Startup error: $e')),
        ),
      ),
    );
  }
}

/// Branded splash shown while the device identity is being loaded.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient(),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppTheme.lg),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.card,
                    border: Border.all(
                      color: AppTheme.brandGreen.withValues(alpha: 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.brandGreen.withValues(alpha: 0.18),
                        blurRadius: 40,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/branding/app_logo.png',
                    width: 72,
                    height: 72,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: AppTheme.xl),
                Text(
                  'Bitconnect',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppTheme.sm),
                Text(
                  'Mesh messaging, offline & worldwide',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: AppTheme.xxl),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: AppTheme.brandGreen,
                    strokeWidth: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
