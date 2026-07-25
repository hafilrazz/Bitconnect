# Netless

**Offline Bluetooth mesh chat + worldwide end-to-end encrypted DMs.**

No accounts. No phone numbers. No app server of your own for DMs — internet messages ride public Nostr relays as **ciphertext only**.

---

## Features

| Mode | When to use | Privacy |
|---|---|---|
| **Local mesh** (`#local`) | Same room, concert, campus, disaster — no internet | Public to the mesh (signed, not private) |
| **Worldwide E2E** | India ↔ USA or any distance with internet | **Pure E2E** 1:1 DMs |

### Local mesh (Bluetooth)

- Multi-hop BLE gossip (devices relay for each other)
- Ed25519-signed channel posts
- Default channel: `#local`
- Android dual-role BLE (advertise + scan/connect)

### Worldwide E2E (Internet)

- Private **1:1** messages over public Nostr relays
- **X25519 ECDH + ChaCha20-Poly1305** encryption on-device
- **Ed25519** authenticity of the sealed box
- Relays **cannot read** message text  
  Details: [docs/E2E_INTERNET.md](docs/E2E_INTERNET.md)

### Not included (yet)

- Group E2E / public global channels
- Media attachments
- Store-and-forward “ferry” over days offline
- Play Store / App Store release signing pipeline

---

## Install the Android app

Prebuilt release APK (sideload):

```
C:\netless\dist\netless-release.apk
```

Or rebuild:

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;C:\Users\hafil\flutter\bin;$env:PATH"

cd C:\netless\apps\mobile
flutter pub get
flutter build apk --release
# APK: build\app\outputs\flutter-apk\app-release.apk
```

**Requirements:** Android 8+ (API 26), Bluetooth for mesh, Internet for worldwide DMs.

### USB install

```powershell
adb install -r C:\netless\dist\netless-release.apk
```

---

## App UX (what you see)

Bottom navigation:

1. **Local mesh** — `#local` channel, start/stop mesh, peer count, message list  
2. **Worldwide** — copy your Netless ID, add a contact, connect relays, send 🔒 DMs  

Onboarding sets a nickname and explains both modes.

### Local mesh — quick use

1. Open **Local mesh** → **Start mesh** (or send a message to auto-start).
2. Grant Bluetooth / nearby-device permissions.
3. On a second phone with Netless nearby, start mesh and chat on `#local`.
4. Menu (⋮): switch **Bluetooth** vs **Simulator**, inject a fake hop, clear history.

### Worldwide E2E — India ↔ USA

1. Open **Worldwide** on both phones (both need internet).
2. Each taps **Copy my ID** and shares it (any channel).
3. **Add contact** → paste their Netless ID → **Save & chat**.
4. Tap **Connect**, then send. Messages are encrypted **before** leaving the phone.

---

## Repo layout

```
apps/mobile/              Flutter UI (Material 3)
packages/
  mesh_protocol/          Packets, gossip, Ed25519, E2E crypto (pure Dart)
  mesh_transport/         FakeTransport + sim fabric
  mesh_ble/               BLE central + Android dual-role bridge
  mesh_internet/          Nostr client + InternetE2eService
docs/
  PROTOCOL.md             Mesh wire format
  E2E_INTERNET.md         Internet E2E threat model
  DEMO.md                 Multi-phone demo checklist
dist/
  netless-release.apk     Sideload build (when built)
```

---

## Develop

### Prerequisites

- Flutter **3.22+** (this machine: `C:\Users\hafil\flutter`)
- **JDK 17** for Android Gradle (JDK 26 is too new for current Gradle)
- Android SDK (`%LOCALAPPDATA%\Android\Sdk`)

```powershell
$env:PATH = "C:\Users\hafil\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"
flutter doctor
```

### Run

```powershell
cd C:\netless\apps\mobile
flutter pub get
flutter run
```

### Tests

```powershell
cd C:\netless\packages\mesh_protocol
dart pub get
dart test
```

Includes multi-hop gossip sims and E2E seal/open tests.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│  Flutter UI  (Local mesh | Worldwide E2E)   │
├──────────────────┬──────────────────────────┤
│  MeshNode        │  InternetE2eService      │
│  (gossip, TTL)   │  (seal box → Nostr)      │
├──────────────────┼──────────────────────────┤
│  BLE / Fake      │  Nostr WebSocket relays  │
└──────────────────┴──────────────────────────┘
```

- `mesh_protocol` has **no Flutter dependency** — unit-testable.
- Mesh identity: Ed25519 (sign). Encryption identity: X25519 (E2E).
- Netless ID (shareable) = **X25519 public key hex** (64 chars).

---

## Security notes

| Surface | Behavior |
|---|---|
| `#local` mesh | **Not confidential** — anyone on the mesh can read |
| Internet DMs | **E2E confidential + authenticated** |
| Nicknames | Not unique; trust fingerprint / Netless ID |
| Relays | Untrusted; see only ciphertext + coarse metadata |
| Keys | Stored in `flutter_secure_storage` |

Do **not** put secrets on `#local`. Use **Worldwide E2E** for private remote chat.

---

## Platform notes

| Platform | Local mesh background | Internet E2E |
|---|---|---|
| **Android** | Works in foreground; keep app open for best mesh | Works with network permission |
| **iOS** | Scaffolded; BLE background is best-effort | Same client code; build with Xcode |

---

## UX status

| Area | Status |
|---|---|
| Onboarding (nickname + mode explainer) | Done |
| Bottom nav Local / Worldwide | Done |
| Mesh status chips, empty states, start CTA | Done |
| E2E contact add/copy ID, connect, locked bubbles | Done |
| Timestamps, scroll-to-latest | Done |
| Production polish (QR codes, push, read receipts, theming, a11y audit) | **Not done** |

The UI is **usable for demos and real E2E testing**, not a finished consumer chat product.

---

## License

MIT — see [LICENSE](LICENSE).
