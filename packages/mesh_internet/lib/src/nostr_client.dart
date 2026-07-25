import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'nostr_keys.dart';

typedef NostrEventHandler = void Function(NostrEvent event, String relayUrl);

/// Minimal multi-relay Nostr client (publish + subscribe).
class NostrClient {
  NostrClient({
    List<String>? relays,
    this.onEvent,
    this.onStatus,
  }) : relays = relays ?? defaultRelays;

  static const defaultRelays = <String>[
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.primal.net',
    'wss://offchain.pub',
  ];

  final List<String> relays;
  final NostrEventHandler? onEvent;
  final void Function(String message)? onStatus;

  final Map<String, WebSocketChannel> _channels = {};
  final Map<String, StreamSubscription> _subs = {};
  bool _running = false;
  int _subCounter = 0;

  bool get isRunning => _running;
  int get connectedCount => _channels.length;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    for (final url in relays) {
      unawaited(_connect(url));
    }
  }

  Future<void> _connect(String url) async {
    if (!_running) return;
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _channels[url] = ch;
      onStatus?.call('connected $url');
      _subs[url] = ch.stream.listen(
        (data) => _onMessage(url, data),
        onError: (_) {
          onStatus?.call('error $url');
          _drop(url);
          _scheduleReconnect(url);
        },
        onDone: () {
          onStatus?.call('closed $url');
          _drop(url);
          _scheduleReconnect(url);
        },
        cancelOnError: true,
      );
    } catch (e) {
      onStatus?.call('fail $url: $e');
      _scheduleReconnect(url);
    }
  }

  void _drop(String url) {
    _subs.remove(url)?.cancel();
    try {
      _channels.remove(url)?.sink.close();
    } catch (_) {}
  }

  void _scheduleReconnect(String url) {
    if (!_running) return;
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (_running && !_channels.containsKey(url)) {
        unawaited(_connect(url));
      }
    });
  }

  void _onMessage(String url, dynamic data) {
    try {
      final msg = jsonDecode(data as String);
      if (msg is! List || msg.isEmpty) return;
      final type = msg[0];
      if (type == 'EVENT' && msg.length >= 3) {
        final raw = msg[2];
        if (raw is Map<String, dynamic>) {
          final ev = NostrEvent.fromJson(raw);
          onEvent?.call(ev, url);
        } else if (raw is Map) {
          final ev = NostrEvent.fromJson(Map<String, dynamic>.from(raw));
          onEvent?.call(ev, url);
        }
      } else if (type == 'NOTICE' && msg.length >= 2) {
        onStatus?.call('notice $url: ${msg[1]}');
      }
    } catch (_) {}
  }

  /// Subscribe for Netless E2E DMs addressed to [recipientTag] (our netless id).
  String subscribeForRecipient(String recipientTag, {int? since}) {
    final subId = 'nl${_subCounter++}';
    final filter = <String, dynamic>{
      'kinds': [NostrEvent.kindE2eDm],
      '#p': [recipientTag],
    };
    if (since != null) filter['since'] = since;
    final req = jsonEncode(['REQ', subId, filter]);
    _broadcast(req);
    return subId;
  }

  void publish(NostrEvent event) {
    final msg = jsonEncode(['EVENT', event.toJson()]);
    _broadcast(msg);
  }

  void _broadcast(String msg) {
    for (final e in _channels.entries) {
      try {
        e.value.sink.add(msg);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _running = false;
    for (final url in _channels.keys.toList()) {
      _drop(url);
    }
  }
}
