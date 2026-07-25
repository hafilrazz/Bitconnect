# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:/netless")

def w(rel, content):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content.replace("\r\n", "\n"), encoding="utf-8")
    print("wrote", rel)

w(".gitignore", """# Flutter/Dart
.dart_tool/
.packages
build/
.flutter-plugins
.flutter-plugins-dependencies
.pub-cache/
.pub/
**/doc/api/
*.iml
.idea/
.vscode/

# OS
.DS_Store
Thumbs.db

# Secrets
*.jks
key.properties
local.properties
""")

w("README.md", """# Netless

Offline Bluetooth mesh chat. Messages hop device-to-device over BLE — no internet, no cell, no servers.

## What it is

Netless is a Flutter app for **public channel chat** on an ad-hoc BLE multi-hop mesh (Bridgefy / Bitchat-style). Every phone advertises, scans, and relays. Messages are **Ed25519-signed** so you can verify authorship even though nicknames are free-form.

### MVP scope

- Multi-hop gossip flood on a default `#local` channel
- Pseudonymous identity (Ed25519 keypair + nickname)
- Installable Android + iOS demo for a crowded venue (about 5-20 phones)
- Protocol logic in pure Dart (unit-tested without phones)

### Not in MVP

- Private DMs / E2E (phase 2 — keypairs are ready)
- Internet / Nostr bridge
- Long-term store-and-forward ferry
- Images or large attachments

## Repo layout

```
apps/mobile/           Flutter app (UI + wiring)
packages/
  mesh_protocol/       Packet codec, crypto, gossip (pure Dart)
  mesh_transport/      Transport interface + FakeTransport simulator
  mesh_ble/            BLE implementation (flutter_blue_plus)
docs/
  PROTOCOL.md          Wire format and mesh rules
  DEMO.md              How to run a multi-phone demo
```

## Prerequisites

- Flutter 3.22+ (stable)
- Android SDK and/or Xcode for device builds
- Physical phones for real multi-hop (BLE does not work in most emulators)

```powershell
$env:PATH = "C:\\Users\\hafil\\flutter\\bin;$env:PATH"
flutter doctor
```

## Quick start

```bash
cd apps/mobile
flutter pub get
flutter test
flutter run
```

Protocol package tests:

```bash
cd packages/mesh_protocol
dart pub get
dart test
```

### Simulated mesh (no BLE)

Default debug mode uses `FakeTransport` so you can exercise multi-hop gossip without radios. Protocol package tests cover line and diamond topologies.

### Real BLE

1. Install on two or more physical devices.
2. Grant Bluetooth permissions; on Android allow the foreground service notification.
3. Turn mesh **On**, join `#local`, send a message.
4. For a 3-hop proof: A and C out of range with B in the middle. See [docs/DEMO.md](docs/DEMO.md).

## Architecture

```
UI -> Identity / MessageStore -> MeshNode (gossip) -> MeshTransport -> BLE
```

- `mesh_protocol` never imports Flutter.
- Platforms only move bytes; TTL, dedup, and signatures are shared Dart.

## Identity and security

- First launch generates an Ed25519 keypair in secure storage.
- Public channel posts are signed; receivers drop invalid signatures.
- Nicknames are not unique — trust the short pubkey fingerprint.
- `#local` is public to anyone in the mesh. Do not send secrets there.

## Platform notes

| Platform | Mesh while backgrounded |
|---|---|
| Android | Foreground service keeps mesh alive while Mesh on |
| iOS | Best-effort with BLE background modes; demo with app open |

## License

MIT
""")

w("docs/PROTOCOL.md", """# Netless mesh protocol v1

Application-level BLE gossip. Not Bluetooth SIG Mesh.

## Packet layout

All multi-byte integers are **big-endian**.

| Field | Size | Notes |
|---|---|---|
| magic | 2 | 0x4E54 (NT) |
| version | 1 | 1 |
| type | 1 | 1=CHAT, 2=ANNOUNCE |
| ttl | 1 | hops remaining |
| flags | 1 | reserved 0 |
| channel_id | 2 | #local = 1 |
| msg_id | 16 | random UUID bytes |
| sender_pk | 32 | Ed25519 public key |
| timestamp | 4 | Unix seconds |
| nickname_len | 1 | 0-24 |
| nickname | N | UTF-8 |
| body_len | 2 | 0-200 for MVP |
| body | M | UTF-8 |
| signature | 64 | Ed25519 over sign payload |

### Sign payload

```
version || type || channel_id || msg_id || sender_pk || timestamp || nickname_bytes || body
```

## Gossip rules

1. Create: TTL = MAX_TTL (7), new msg_id, sign, store, send to all peers.
2. Receive: drop bad magic/version, duplicates, bad signature, timestamp skew; else deliver and forward with ttl-1.

## Limits

- Nickname <= 24 UTF-8 bytes
- Body <= 200 UTF-8 bytes
- Default max TTL = 7
""")

w("docs/DEMO.md", """# Demo guide

## Two phones (single hop)

1. Install on phone A and B.
2. Enable Bluetooth. Open Netless, set nicknames.
3. Turn Mesh On on both; wait for peer count >= 1.
4. Send on #local from A; B should show it.

## Three phones (multi-hop)

Topology A -- B -- C with A and C not direct peers.

1. Space A and C far apart; B mid-path.
2. Mesh on all three.
3. A sends hop test; C receives via B.

## Acceptance

- [ ] Works in airplane mode
- [ ] Invalid signatures never appear
- [ ] No duplicate msg_id in timeline
- [ ] Multi-hop observed at least once
""")

print("batch1 done")
