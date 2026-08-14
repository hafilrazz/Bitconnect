import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mesh_controller.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'internet_dm_screen.dart';

/// Bottom-nav shell: Local mesh vs Worldwide E2E.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  MeshController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = await ref.read(meshControllerBootstrapProvider.future);
    if (mounted) setState(() => _controller = c);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return Scaffold(
        backgroundColor: AppTheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.brandGreen),
              const SizedBox(height: 12),
              Text(
                'Starting Bitconnect…',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          LocalMeshPage(controller: c),
          InternetDmScreen(controller: c, embedded: true),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: c,
        builder: (context, _) => NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: c.meshOn,
                smallSize: 8,
                backgroundColor: AppTheme.brandGreen,
                child: Icon(
                  c.meshOn
                      ? Icons.wifi_tethering
                      : Icons.wifi_tethering_off_outlined,
                ),
              ),
              selectedIcon: const Icon(Icons.wifi_tethering),
              label: 'Local',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: c.internetOn,
                smallSize: 8,
                backgroundColor: AppTheme.brandGreen,
                child: Icon(c.internetOn ? Icons.lock : Icons.public_outlined),
              ),
              selectedIcon: const Icon(Icons.lock),
              label: 'Worldwide',
            ),
          ],
        ),
      ),
    );
  }
}
