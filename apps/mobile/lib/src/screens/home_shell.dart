import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mesh_controller.dart';
import '../providers.dart';
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
    c.addListener(() {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _controller = c);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Icon(
              c.meshOn ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            ),
            label: 'Local mesh',
          ),
          NavigationDestination(
            icon: Icon(c.internetOn ? Icons.lock : Icons.public),
            label: 'Worldwide',
          ),
        ],
      ),
    );
  }
}
