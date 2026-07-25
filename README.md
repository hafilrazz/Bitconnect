# Netless

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
$env:PATH = "C:\Users\hafil\flutter\bin;$env:PATH"
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
