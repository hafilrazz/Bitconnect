import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import 'identity_store.dart';
import 'mesh_controller.dart';

final identityStoreProvider = Provider((ref) => IdentityStore());

final appIdentityProvider = FutureProvider<AppIdentity>((ref) async {
  final store = ref.watch(identityStoreProvider);
  return store.loadOrCreate();
});

final identityProvider = FutureProvider<CryptoIdentity>((ref) async {
  final app = await ref.watch(appIdentityProvider.future);
  return app.sign;
});

final nicknameProvider = FutureProvider<String?>((ref) async {
  return ref.watch(identityStoreProvider).getNickname();
});

final identityReadyProvider = FutureProvider<bool>((ref) async {
  await ref.watch(appIdentityProvider.future);
  final nick = await ref.watch(nicknameProvider.future);
  return nick != null && nick.isNotEmpty;
});

final meshControllerBootstrapProvider =
    FutureProvider<MeshController>((ref) async {
  final app = await ref.watch(appIdentityProvider.future);
  final store = ref.watch(identityStoreProvider);
  final c = MeshController(appIdentity: app);
  c.contacts = await store.loadContacts();
  if (c.contacts.isNotEmpty) {
    c.activePeerId = c.contacts.first.netlessId;
  }
  // Persist contacts when changed — lightweight poll via listener
  c.addListener(() {
    store.saveContacts(c.contacts);
  });
  ref.onDispose(c.dispose);
  return c;
});
