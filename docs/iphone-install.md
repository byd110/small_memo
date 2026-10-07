# Install Small Memo on your own iPhone

You need a Mac, an iPhone running iOS 15 or newer, a USB cable, and a free Apple
Account. No App Store submission or paid membership is needed for this route.
A free Personal Team installation expires after seven days and must be signed
and installed again. The Mac needs an Xcode version that supports your iPhone's
iOS version; older Macs may not support the necessary Xcode release.

## 1. Prepare your Mac

1. Install Xcode from the Mac App Store. Open it once and let it install its
   components and iOS platform support.
2. Install Flutter using the [macOS setup guide](https://docs.flutter.dev/install).
   This project uses Flutter **3.47.6**. Make sure `flutter` is on your PATH.
3. In Terminal, select and initialize Xcode:

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   sudo xcodebuild -license
   flutter doctor -v
   ```

   Review and accept Apple's license when prompted. Resolve any iOS/Xcode errors
   reported by `flutter doctor`. Android warnings can be ignored for iPhone setup.
   If doctor reports missing iOS platform support, run
   `xcodebuild -downloadPlatform iOS`. Follow doctor's CocoaPods instructions if
   it reports that CocoaPods is required by your installed tooling or plugins.

## 2. Download and prepare the project

```sh
git clone https://github.com/byd110/small_memo.git
cd small_memo
flutter pub get
flutter build ios --config-only --no-codesign
open ios/Runner.xcworkspace
```

If you already cloned the project, use that copy and `git pull` instead. Open the
**workspace**, not just the `.xcodeproj`. The configuration-only command prepares
Flutter's generated files; it does not install the app or bypass signing.

## 3. Connect and configure your iPhone

1. Connect it to the Mac, unlock it, and accept **Trust This Computer**.
2. In Xcode, open **Settings > Accounts** (named Apple Accounts in some versions)
   and sign in to your Apple Account.
3. In the project navigator select **Runner**, then the **Runner app target**,
   then **Signing & Capabilities**.
4. Enable **Automatically manage signing**. Select your **Personal Team**.
5. Set a unique bundle identifier, for example `com.byd110.smallmemo`. If Xcode
   reports that it is unavailable, add a unique suffix. Apply the same team and
   identifier to all build configurations. Do not change them between updates.
6. Select your actual iPhone as the run destination in Xcode's toolbar. Do not
   choose a simulator or a generic "Any iOS Device" destination.
7. On iOS 16 or newer, enable **Settings > Privacy & Security > Developer Mode**,
   restart the phone, and confirm. If this option is missing, first let Xcode
   pair/configure the connected phone in **Window > Devices and Simulators**.

These signing choices are personal to you. Keep them in your Mac checkout; do
not commit signing credentials, certificates, or private keys to the public repo.

## 4. Install a Release build for everyday use

In Xcode:

1. Choose **Product > Scheme > Edit Scheme**.
2. Select **Run**, then **Info**, and set **Build Configuration** to **Release**.
3. Press the Run triangle (or **Command-R**) with the iPhone selected.
4. Allow Xcode to create the development certificate/profile if prompted. If
   Keychain asks about `codesign`, authorize access using your Mac password.
5. If the phone reports an untrusted developer, go to **Settings > General >
   VPN & Device Management**, select your developer identity, and trust it.
   Return to Xcode and run again if needed.

After the app launches, stop the Xcode run, disconnect, and open **Small Memo**
from the home screen. Release mode is intended for this standalone use; Debug
mode is for an attached development/debugging session.

Alternatively, after configuring signing in Xcode, install from Terminal:

```sh
flutter devices
flutter run --release -d YOUR_IPHONE_DEVICE_ID
```

Replace the placeholder with the iPhone identifier printed by `flutter devices`.

## 5. Renew the free installation

When the seven-day provisioning period expires, reconnect the phone and repeat
step 4. Keep the same bundle identifier and team, and install over the existing
app. **Do not delete the app first**: its tasks are local and deleting it can
remove them. There is currently no cross-device sync or in-app export feature.

If installation fails, start with the full message under Xcode's Signing &
Capabilities panel. Common causes are a non-unique bundle identifier, no selected
team, Developer Mode being off, or Xcode being too old for the phone's iOS version.

## References

- [Flutter: iOS setup and device trust](https://docs.flutter.dev/platform-integration/ios/setup)
- [Apple: Personal Team limitations](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Flutter: build modes](https://docs.flutter.dev/testing/build-modes)
