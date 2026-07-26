# Bitconnect mobile app

Flutter client for **Bitconnect** — BLE mesh chat + worldwide E2E DMs.

Full docs: **[../../README.md](../../README.md)**

## Run

```powershell
$env:PATH = "C:\Users\hafil\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"
flutter pub get
flutter run
```

## Release APK (smaller, arm64)

```powershell
flutter build apk --release --split-per-abi
copy build\app\outputs\flutter-apk\app-arm64-v8a-release.apk ..\..\dist\bitconnect-release.apk
```

## Tabs

- **Local** — mesh channels, photos, receipts  
- **Worldwide** — E2E DMs, paste contacts  
- **Settings** — power mode, encrypted groups  
