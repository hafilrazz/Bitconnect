import 'dart:async';
import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';

import 'nostr_client.dart';
import 'nostr_keys.dart';

/// Fully end-to-end encrypted DM over the public internet.
///
/// - Plaintext never leaves the device unencrypted
/// - Nostr relays only store opaque ciphertext (kind 21000)
/// - Recipient is addressed by Netless ID (hex X25519 pubkey)
/// - Authenticity via Ed25519 signature inside the sealed box
class InternetE2eService {
  InternetE2eService({
    required this.signIdentity,
    required this.encIdentity,
    required this.nickname,
    required Uint8List keySeed,
    List<String>? relays,
  }) : _nostrKeys = NostrKeys.fromAppSeed(keySeed) {
    _client = NostrClient(
      relays: relays,
      onEvent: _onNostrEvent,
      onStatus: (m) {
        lastStatus = m;
        _statusController.add(m);
      },
    );
  }

  final CryptoIdentity signIdentity;
  final EncryptionIdentity encIdentity;
  String nickname;

  final NostrKeys _nostrKeys;
  late final NostrClient _client;

  final _messages = StreamController<InternetDm>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final Set<String> _seen = {};

  String? lastStatus;
  bool running = false;

  Stream<InternetDm> get messages => _messages.stream;
  Stream<String> get status => _statusController.stream;
  int get relayCount => _client.connectedCount;

  /// Share this with contacts so they can E2E-message you over the internet.
  String get netlessId => encIdentity.publicKeyHex;

  String get signFingerprint => signIdentity.shortFingerprint;

  Future<void> start() async {
    if (running) return;
    await _client.start();
    // Look back 48h for undelivered DMs
    final since = DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 48))
            .millisecondsSinceEpoch ~/
        1000;
    _client.subscribeForRecipient(netlessId, since: since);
    // Also subscribe to our sign fingerprint tag (legacy/alternate addressing)
    _client.subscribeForRecipient(signIdentity.shortFingerprint, since: since);
    running = true;
    lastStatus = 'internet E2E started; id=${netlessId.substring(0, 12)}…';
    _statusController.add(lastStatus!);
  }

  Future<void> stop() async {
    running = false;
    await _client.stop();
  }

  /// Send pure E2E DM to [recipientNetlessId] (64 hex chars = X25519 pubkey).
  Future<InternetDm> sendDm({
    required String recipientNetlessId,
    required String text,
  }) async {
    final recipientPk = EncryptionIdentity.publicKeyFromHex(recipientNetlessId);
    final sealed = await E2eBox.seal(
      senderSign: signIdentity,
      senderEnc: encIdentity,
      recipientX25519Pk: recipientPk,
      plaintext: text,
      nickname: nickname,
    );

    // Content is ONLY the sealed box JSON — no plaintext fields.
    final content = sealed.encode();
    final event = NostrEvent.signed(
      keys: _nostrKeys,
      kind: NostrEvent.kindE2eDm,
      tags: [
        ['p', recipientNetlessId.toLowerCase()],
        ['netless', 'e2e-v1'],
        ['sep', encIdentity.publicKeyHex],
      ],
      content: content,
    );
    _client.publish(event);

    final dm = InternetDm(
      text: text,
      isLocal: true,
      nickname: nickname,
      peerNetlessId: recipientNetlessId.toLowerCase(),
      senderSignFingerprint: signIdentity.shortFingerprint,
      timestamp: sealed.timestamp,
      e2e: true,
    );
    _messages.add(dm);
    return dm;
  }

  void _onNostrEvent(NostrEvent event, String relayUrl) {
    if (event.kind != NostrEvent.kindE2eDm) return;
    if (event.id.isNotEmpty && !_seen.add(event.id)) return;

    // Must be tagged to us
    final pTags = event.tags
        .where((t) => t.isNotEmpty && t[0] == 'p')
        .map((t) => t.length > 1 ? t[1].toLowerCase() : '')
        .toSet();
    if (!pTags.contains(netlessId.toLowerCase()) &&
        !pTags.contains(signIdentity.shortFingerprint.toLowerCase())) {
      return;
    }

    try {
      final sealed = E2eSealedMessage.decode(event.content);
      // Async open
      unawaited(_openAndEmit(sealed));
    } catch (_) {
      // ignore malformed
    }
  }

  Future<void> _openAndEmit(E2eSealedMessage sealed) async {
    try {
      final opened = await E2eBox.open(
        recipientEnc: encIdentity,
        sealed: sealed,
      );
      final peerId = _toHex(opened.senderEncPk);
      final dm = InternetDm(
        text: opened.plaintext,
        isLocal: false,
        nickname: opened.nickname.isEmpty ? 'peer' : opened.nickname,
        peerNetlessId: peerId,
        senderSignFingerprint: opened.senderFingerprint,
        timestamp: opened.timestamp,
        e2e: true,
      );
      _messages.add(dm);
    } catch (e) {
      lastStatus = 'drop bad E2E: $e';
      _statusController.add(lastStatus!);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _messages.close();
    await _statusController.close();
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

class InternetDm {
  InternetDm({
    required this.text,
    required this.isLocal,
    required this.nickname,
    required this.peerNetlessId,
    required this.senderSignFingerprint,
    required this.timestamp,
    required this.e2e,
  });

  final String text;
  final bool isLocal;
  final String nickname;
  final String peerNetlessId;
  final String senderSignFingerprint;
  final int timestamp;
  final bool e2e;

  String get shortPeer => peerNetlessId.length > 12
      ? '${peerNetlessId.substring(0, 12)}…'
      : peerNetlessId;
}
