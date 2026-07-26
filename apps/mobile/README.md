# Bitconnect mobile app

Flutter client for Bitconnect (BLE mesh + worldwide E2E DMs).

See the [repo README](../../README.md) for architecture and setup.

## Run

```bash
# Ensure Flutter is on PATH
flutter pub get
flutter run
```

### Demo without radios

1. Launch the app, pick a nickname.
2. Tap the tether icon to turn **mesh on** (default transport is Fake/sim).
3. Menu → **Inject simulated remote** to receive a multi-hop message through virtual relays.
4. Type in `#local` to post signed messages.

### Real BLE

Menu → **Transport: BLE**, then mesh on. Requires physical devices and Bluetooth permissions.
