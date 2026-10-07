# Small Memo for Android

The Android app uses the same task list, local storage, and offline behavior as
the other versions. Minimum OS: **Android 7.0 / API 24**. It does not use Google
Play Services, Firebase, a sign-in provider, reminders, or a background service.
The release manifest requests no internet or storage permission. Android cloud
backup is disabled; this is a local-only app, and uninstalling it deletes its data.
Debug builds request internet permission for Flutter's debugger.

## Build and install on your phone

Install [Flutter and the Android tools](https://docs.flutter.dev/platform-integration/android/setup).
Use Flutter 3.47.6, an Android SDK with API 36, and JDK 17 or a compatible newer JDK.
The Flutter/Gradle build installs its required SDK/NDK components if missing and
licenses have been accepted. Run `flutter doctor -v` and
`flutter doctor --android-licenses` to finish setup.

Enable Developer options and USB debugging on the phone, connect it by USB, and
approve the computer's debugging authorization. From the project directory:

```sh
flutter pub get
flutter devices
flutter run --release -d YOUR_ANDROID_DEVICE_ID
```

This installs the native app for personal use. Open it from the home screen after
disconnecting. There is no seven-day Apple-style provisioning expiry.

To create an APK for manual installation:

```sh
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`. Transfer that file to
your phone and open it. If requested, allow installation from that particular
browser/file manager. Manufacturer, region, and device-management policies can
restrict manual installation; USB development installation is the alternative.

## Signing and keeping your tasks through updates

By default, local builds use your computer's Android **debug signing key**, even
in release mode. This makes initial personal testing easy. Keep using the same
computer/key for updates. CI uploads an artifact named
`small-memo-android-test-apk`; its signing key is temporary and may change between
runs. It is for testing, not a stable update channel or a Play Store release.

Android accepts an update only when the application ID and signing identity
match the installed version. A different signing key can force an uninstall,
which deletes local tasks. For ongoing use, create and back up a private key
before you start keeping important tasks in the app.

The project supports an optional private `android/key.properties` file:

```properties
storeFile=/absolute/path/to/small-memo.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=smallmemo
keyPassword=YOUR_KEY_PASSWORD
```

For example, create a key with the JDK's `keytool` (replace the output path):

```sh
keytool -genkeypair -v -keystore /absolute/path/to/small-memo.jks -alias smallmemo -keyalg RSA -keysize 2048 -validity 10000
```

Enter passwords interactively, then put the matching values in the properties
file. Build with `flutter build apk --release` again. The build uses this private
key whenever the file exists. Keep both the key and passwords backed up securely;
keystores and `key.properties` are excluded from Git. Never upload them to the
public repository. On Windows, use forward slashes in the properties path.
See [Android app signing](https://docs.flutter.dev/deployment/android#sign-the-app)
for more details before publishing to an app store.

## Manufacturer compatibility

Compatibility depends on Android API/ABI support, not the marketing name alone.
This is an expected compatibility assessment, not a claim of testing on each
manufacturer's phones.

| Phone system | Expected behavior |
| --- | --- |
| Google/standard Android, Samsung One UI | Same APK on supported Android versions. |
| OPPO ColorOS, OnePlus OxygenOS, Xiaomi HyperOS | Same APK on their Android-based phones. |
| HONOR MagicOS | Same APK on its Android-based phones; MagicOS is distinct from Huawei HarmonyOS. |
| Huawei EMUI / older Android-compatible HarmonyOS phones | Expected to work if the device supports Android API 24+ and installation of this APK. Google services are not required. |
| HarmonyOS NEXT / HarmonyOS 5 and later | Not a native HarmonyOS app. Some devices offer Android compatibility software, but installation and behavior depend on that software and must be tested. Native support would require a separate port. |

Huawei's current instructions describe installing some APKs through compatibility
services such as 卓易通 (DroiTong), and explicitly make support conditional on
that service. Do not assume that either every APK works or no APK can run on all
new HarmonyOS devices. Confirm the exact phone model, region, OS version, and
compatibility service before buying specifically for this app.

Sources checked October 7, 2026:

- [OPPO: Android-based ColorOS](https://www.oppo.com/uk/coloros12/)
- [HONOR: MagicOS based on Android](https://www.honor.com/sa-en/phones/honor-magic7-pro/spec/)
- [Huawei: HarmonyOS 5+ app installation (Chinese)](https://consumer.huawei.com/cn/support/content/zh-cn16061787/)
