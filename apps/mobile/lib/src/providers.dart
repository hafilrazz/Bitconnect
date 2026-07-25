import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import 'identity_store.dart';
import 'mesh_controller.dart';

final identityStoreProvider = Provider((ref) => IdentityStore());

final identityProvider = FutureProvider<CryptoIdentity>((ref) async {
  return ref.watch(identityStoreProvider).loadOrCreateIdentity();
});

final nicknameProvider = FutureProvider<String?>((ref) async {
  return ref.watch(identityStoreProvider).getNickname();
});

/// true if nickname already set
final identityReadyProvider = FutureProvider<bool>((ref) async {
  await ref.watch(identityProvider.future);
  final nick = await ref.watch(nicknameProvider.future);
  return nick != null && nick.isNotEmpty;
});

final meshControllerProvider =
    ChangeNotifierProvider<MeshController?>((ref) {
  // Created after onboarding via override / manual; see bootstrap.
  return null;
});

final meshControllerBootstrapProvider =
    FutureProvider<MeshController>((ref) async {
  final id = await ref.watch(identityProvider.future);
  final nick =
      await ref.watch(identityStoreProvider).getNickname() ?? 'anon';
  // On real Android devices default to BLE so sideloaded builds just work.
  final mode = (!kIsWeb && Platform.isAndroid)
      ? TransportMode.ble
      : TransportMode.fake;
  final c = MeshController(identity: id, nickname: nick, mode: mode);
  ref.onDispose(c.dispose);
  return c;
});
