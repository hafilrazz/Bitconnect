# Bitconnect

**Offline Bluetooth mesh chat + worldwide end-to-end encrypted DMs.**

No accounts. No phone numbers. Messages hop phone-to-phone over BLE when offline, or travel the world as pure E2E ciphertext over public Nostr relays.

| | |
|---|---|
| **Product name** | Bitconnect |
| **Version** | 0.2+ (mesh protocol v2) |
| **Platforms** | Android (primary), iOS scaffolded |
| **Workspace path** | `C:\netless` (folder name is historical; product is Bitconnect) |

---

## What you can do

### Local mesh (Bluetooth)

- Multi-hop BLE gossip on **multiple channels** (`#local`, `#general`, `#alerts`, custom)
- **High TX power** + low-latency scan for better practical range
- Phones relay for each other (effective range grows with density)
- **Signed** public posts (Ed25519); optional **group E2E** with a shared channel key
- **Images over mesh** — compressed, multi-chunk transfer, **one bubble**, **tap to open** full screen
- Delivery **ACKs** and **read receipts** (✓ / ✓✓)
- **Store-and-forward ferry** for text when peers reappear
- **Power modes**: Performance / Balanced / Saver (LPN-style)

### Worldwide E2E (Internet)

- Private **1:1 DMs** India ↔ USA (or any distance) when both have internet
- **X25519 ECDH + ChaCha20-Poly1305** encryption on-device
- Relays **cannot read** message text
- Share identity via **QR code**, **copy ID**, or **paste** (camera has paste fallback)

### Not private

- Default mesh channels (`#local`, etc.) are **readable by anyone on the mesh**
- Use **Create E2E group** in Settings for encrypted local rooms

---

## Install (Android)

### APK

```
dist/bitconnect-release.apk
```

Most modern phones: **arm64**. Prefer a **split ABI** build for smaller size (see below).

```powershell
adb install -r dist\bitconnect-release.apk
```

Or copy the APK to the phone and open it (allow install from unknown sources).

**Requirements:** Android 8+ (API 26), Bluetooth for mesh, Internet for Worldwide DMs, Camera optional for QR scan.

### Smaller APKs (recommended)

A single “fat” APK bundles multiple CPU architectures (~70MB+). Split builds are much smaller:

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;C:\Users\hafil\flutter\bin;$env:PATH"

cd apps/mobile
flutter pub get
flutter build apk --release --split-per-abi
```

Outputs:

| File | Use |
|---|---|
| `app-arm64-v8a-release.apk` | Most modern phones (**use this**) |
| `app-armeabi-v7a-release.apk` | Older 32-bit phones |
| `app-x86_64-release.apk` | Emulators |

Copy the one you need:

```powershell
copy build\app\outputs\flutter-apk\app-arm64-v8a-release.apk ..\..\dist\bitconnect-release.apk
```

---

## App map (UI)

Bottom navigation:

| Tab | Purpose |
|---|---|
| **Local** | Mesh channel chat, start/stop mesh, photos, receipts |
| **Worldwide** | E2E DMs, connect relays, contacts |

In-app:

| Entry | Purpose |
|---|---|
| **QR** (icon) | Show your Bitconnect ID QR; scan or paste a friend’s ID |
| **Tune / Settings** | Power mode, public channels, create/join encrypted groups |
| **Channel chips** | Switch `#local` / custom channels |
| **Image** | Attach photo (mesh: compressed multi-chunk; Worldwide: larger) |
| **Tap image** | Full-screen pinch-zoom viewer |

### QR scanner notes

- Live **camera stream** + **QR-only** decode (`camera` + on-device QR decode).
- Allow **Camera** when prompted.
- If camera fails: use **Paste** / **Add contact** — same result as scanning.

### Mesh images notes

- **Compress** for mesh: max **448px**, JPEG ~**45 KB** target.
- **Binary file packet** (TLV: name / size / mime / content) — not JSON base64 chat spam.
- Split into **binary BLE fragments**, reassembled into **one bubble**.
- **Tap the thumbnail** → full-screen open.
- Prefer **Worldwide** only if you need much larger photos.

---

## First-run flows

### Local mesh demo (two phones)

1. Install Bitconnect on both devices.
2. Set nicknames.
3. **Local** → start mesh (tether icon) → allow Bluetooth / nearby devices.
4. Chat on `#local`. Keep the app open for best results.
5. Optional: ⋮ menu → Simulator mode for single-device multi-hop tests.

### Worldwide E2E (any distance)

1. Both phones online.
2. **Worldwide** (or QR) → **Copy my ID** / show QR.
3. Friend scans QR or pastes your ID → **Save & chat**.
4. **Connect** relays → send locked messages.

### Encrypted local group

1. Settings → channel name → **Create E2E group**.
2. Share the key out-of-band (secure chat / in person).
3. Friend: Settings → paste key → **Join encrypted channel**.

---

## Repo layout

```
apps/mobile/                 Flutter app (Material 3 dark theme)
  assets/branding/           App logo
  lib/src/
    theme/                   Brand theme
    screens/                 Local, Worldwide, QR, Settings, image viewer
    widgets/                 Bubbles, chips, composer
packages/
  mesh_protocol/             Packets, gossip, crypto, ferry, media chunks (pure Dart)
  mesh_transport/            FakeTransport + multi-node sim fabric
  mesh_ble/                  BLE central + Android dual-role bridge
  mesh_internet/             Nostr client + Internet E2E service
docs/
  PROTOCOL.md                Mesh wire format
  E2E_INTERNET.md            Internet E2E threat model
  DEMO.md                    Multi-phone demo checklist
dist/
  bitconnect-release.apk     Installable build (when present)
```

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Flutter UI  (Local | Worldwide)                 │
│  Theme · QR · Settings · Image viewer            │
├────────────────────┬─────────────────────────────┤
│  MeshController    │  Identity (Ed25519+X25519)  │
├────────────────────┼─────────────────────────────┤
│  MeshNode          │  InternetE2eService          │
│  gossip · ACK/read │  Nostr relays (ciphertext)  │
│  ferry · rate limit│  X25519 sealed boxes        │
│  group crypto      │                             │
│  media chunks      │                             │
├────────────────────┼─────────────────────────────┤
│  BLE / Fake        │  WebSocket relays           │
└────────────────────┴─────────────────────────────┘
```

- `mesh_protocol` has **no Flutter dependency** — unit-tested.
- **Bitconnect ID** (shareable) = X25519 public key hex (64 chars).

### Internal IDs (kept on purpose)

| Item | Value | Why |
|---|---|---|
| Android `applicationId` | `app.netless.netless` | Stable installs/upgrades |
| Flutter package name | `netless` | Import / path stability |
| Secure storage keys | `netless_*` | Existing identities still load |
| Protocol tags | `netless-e2e-v1`, magic `NT` | Wire compatibility |

---

## Develop

### Prerequisites

- Flutter 3.22+ (e.g. `C:\Users\hafil\flutter`)
- **JDK 17** for Android builds (JDK 26 is too new for current Gradle)
- Android SDK (`%LOCALAPPDATA%\Android\Sdk`)

```powershell
$env:PATH = "C:\Users\hafil\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"
flutter doctor
```

### Run

```powershell
cd apps/mobile
flutter pub get
flutter run
```

### Tests

```powershell
cd packages/mesh_protocol
dart pub get
dart test
```

Covers multi-hop gossip, E2E seal/open, rate limit, ferry, group crypto.

---

## Security summary

| Surface | Behavior |
|---|---|
| Public mesh channels | Not confidential — anyone on the mesh can read |
| Encrypted mesh groups | Shared-key E2E (share key out-of-band) |
| Worldwide DMs | Pure E2E; relays see ciphertext only |
| Nicknames | Not unique — trust fingerprint / Bitconnect ID |
| Keys | `flutter_secure_storage` on device |

Do **not** put secrets on open `#local`. Use Worldwide E2E or an encrypted group.

Details: [docs/E2E_INTERNET.md](docs/E2E_INTERNET.md) · [docs/PROTOCOL.md](docs/PROTOCOL.md)

---

## Known limits

| Topic | Reality |
|---|---|
| BLE range | ~tens of meters per hop; multi-hop needs intermediate phones |
| Mesh images | Small thumbnails by design; large photos use Worldwide |
| Background mesh | Best with app open; iOS dual-role is best-effort |
| Nostr delivery | Depends on public relays (no guarantee like WhatsApp) |
| Camera QR | Some OEMs flaky — **paste ID** always works |
| App size | Prefer `--split-per-abi`; fat APK is large due to camera/ML + multi-ABI |
| Signing | Release APK uses debug signing (sideload OK, not Play Store) |

---

## Demo checklist

See [docs/DEMO.md](docs/DEMO.md) for two-phone mesh, multi-hop, and Worldwide E2E acceptance steps.

---

## License

MIT — see [LICENSE](LICENSE).
