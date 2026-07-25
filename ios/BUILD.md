# Gixbee iOS build (macOS + Xcode required)

Windows cannot compile, sign, or run an iOS app. Use a Mac (or a macOS CI
runner such as Codemagic / GitHub Actions `macos-latest`).

## Identifiers

| Item | Value |
|------|--------|
| Display name | `Gixbee` |
| iOS bundle ID | `com.gixbee` (matches `lib/firebase_options.dart` → `iosBundleId`) |
| Android applicationId | `com.gixbeesolution` (different on purpose — Firebase already registered iOS as `com.gixbee`) |
| Minimum iOS | **15.0** (required by `firebase_core` / `firebase_messaging`) |

## One-time Mac setup

1. Install Xcode (App Store) + Command Line Tools, then:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo gem install cocoapods   # or brew install cocoapods
   ```
2. Apple Developer Program account (paid) for device/TestFlight/App Store builds.
3. Open `ios/Runner.xcworkspace` in Xcode → **Signing & Capabilities**:
   - Team: your Apple team
   - Bundle Identifier: `com.gixbee`
   - Ensure **Push Notifications** is present (entitlements already include `aps-environment`)
   - Background Modes → Remote notifications (also set in `Info.plist`)
4. **Firebase / FCM** — Android already has `android/app/google-services.json`.
   Download the matching iOS file from Firebase Console → project `gixbee-fcd03`
   → iOS app `1:434757428061:ios:54e9f836da4330fd0dfeb4` → place at:
   ```
   ios/Runner/GoogleService-Info.plist
   ```
   Do **not** invent this file. It is gitignored (same as Android’s JSON).
   Confirm the plist `BUNDLE_ID` is `com.gixbee`.
5. Optional app icons:
   ```bash
   dart run flutter_launcher_icons
   ```
   (`pubspec.yaml` has `flutter_launcher_icons.ios: true`)

## MapLibre / Ola Maps

- No special Podfile MapLibre lines (plugin ≥ 0.17 handles pods itself).
- Ola API key is a Dart define only — same as Android:
  `--dart-define=OLA_MAPS_API_KEY=…`
- Style JSON is hydrated in Dart (`OlaMapsStyleService`); no iOS Info.plist key.

## Dart defines (same pattern as Android `build_apk.bat` / `gixbee_keys.bat`)

```bash
cd /path/to/gixbee
flutter pub get
cd ios && pod install && cd ..

# Simulator / debug (LAN backend example)
flutter run -d iPhone \
  --dart-define=API_BASE_URL=http://192.168.1.100:3000 \
  --dart-define=SOCKET_URL=http://192.168.1.100:3000 \
  --dart-define=OLA_MAPS_API_KEY=YOUR_OLA_KEY \
  --dart-define=RAZORPAY_KEY=rzp_test_xxx \
  --dart-define=BUILD_VERSION=1.0.0

# Release IPA (device / archive) — needs signing configured in Xcode
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://api.your-domain.com \
  --dart-define=SOCKET_URL=https://api.your-domain.com \
  --dart-define=OLA_MAPS_API_KEY=YOUR_OLA_KEY \
  --dart-define=RAZORPAY_KEY=rzp_live_xxx \
  --dart-define=BUILD_VERSION=1.0.0
```

IPA output: `build/ios/ipa/*.ipa`

For App Store Connect upload you can also archive from Xcode after
`flutter build ios --release` with the same `--dart-define=…` flags.

## Remaining blockers (cannot finish on Windows)

- [ ] Physical Mac or macOS CI
- [ ] Xcode + CocoaPods (`pod install`)
- [ ] Apple Developer account, certificates, provisioning profiles
- [ ] `ios/Runner/GoogleService-Info.plist` from Firebase Console
- [ ] APNs key uploaded to Firebase (Cloud Messaging → Apple app configuration)
- [ ] Real Ola / Razorpay / production API dart-defines for release
