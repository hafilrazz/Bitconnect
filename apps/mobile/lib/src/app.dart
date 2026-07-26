import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';

class BitconnectApp extends ConsumerWidget {
  const BitconnectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(identityReadyProvider);
    return MaterialApp(
      title: 'Bitconnect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6E4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: ready.when(
        data: (hasNick) =>
            hasNick ? const HomeShell() : const OnboardingScreen(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          body: Center(child: Text('Startup error: $e')),
        ),
      ),
    );
  }
}
