import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'screens/chat_screen.dart';
import 'screens/onboarding_screen.dart';

class NetlessApp extends ConsumerWidget {
  const NetlessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(identityReadyProvider);
    return MaterialApp(
      title: 'Netless',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6E4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: ready.when(
        data: (hasNick) =>
            hasNick ? const ChatScreen() : const OnboardingScreen(),
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
