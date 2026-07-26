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
        loading: () => Scaffold(
          backgroundColor: AppTheme.surface,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/branding/app_logo.png', width: 72, height: 72),
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: AppTheme.brandGreen),
              ],
            ),
          ),
        ),
        error: (e, _) => Scaffold(
          body: Center(child: Text('Startup error: $e')),
        ),
      ),
    );
  }
}
