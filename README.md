# Small Memo

A small todo list for **iOS, Android, Windows, and Linux**, built with Flutter.
Create a task, check it off, and get back to what you were doing.

![Small Memo desktop preview with example tasks](docs/preview.png)

## Features

- One list; add tasks with Enter or the + button.
- Log an attempt each time you work on a task. The counter opens a timestamped history.
- Edit a description from the task's menu without losing its attempts or completion state.
- Remove an accidental attempt from its history, with confirmation.
- View attempt summaries for Today, Last 7 days, Last 30 days, All time, or custom dates.
- Check and uncheck tasks independently of attempts. Completed tasks move below unfinished tasks.
- Delete a task with confirmation.
- Save locally first; optionally sign in to sync tasks and attempts across your own devices.
- No reminders. Email/password accounts and sync use Supabase; local-only use remains available.
- Desktop: **Ctrl+Alt+M** restores and focuses the running app, **Ctrl+N**
  focuses task entry, and **Escape** minimizes it. Closing the window quits.
- iOS and Android: launch from the home screen.

The desktop shortcut works only while the app is running. Registration can fail
if another application owns the shortcut. Linux global shortcuts use Keybinder
and target X11; Wayland support is not guaranteed. Use the taskbar if the
shortcut is unavailable. Start-at-login and a system tray are not implemented.

## Development

Install [Flutter](https://docs.flutter.dev/get-started/install). The project was
created using **Flutter 3.47.6 / Dart 3.13.5**; CI uses that Flutter version.

```sh
flutter pub get
flutter analyze
flutter test
```

### Linux (Ubuntu / Debian / Linux Mint)

```sh
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libkeybinder-3.0-dev libsecret-1-dev
flutter run -d linux
flutter build linux --release
```

Run `build/linux/x64/release/bundle/small_memo`. Keep the complete bundle together,
including its `lib` and `data` directories. The target machine needs GTK3 and the
Keybinder runtime (`libkeybinder-3.0-0` on Ubuntu), plus `libsecret-1-0` and
an unlocked Secret Service keyring for saved sign-in sessions.

### Windows

Install Visual Studio with the **Desktop development with C++** workload, then:

```powershell
flutter run -d windows
flutter build windows --release
```

The app is in `build\windows\x64\runner\Release`. Distribute the whole directory,
not just the executable. Target computers need the Visual C++ runtime.

### iOS

Follow the [iPhone installation guide](docs/iphone-install.md) for Xcode setup,
free Personal Team signing, a standalone Release build, and weekly renewal.
The minimum iOS version is 15.0. CI only checks an unsigned build; that build
cannot be installed directly on an iPhone.

### Android

Follow the [Android installation and compatibility guide](docs/android-install.md).
Android 7.0/API 24 or newer is required. Build an APK with:

```sh
flutter build apk --release
```

The APK is at `build/app/outputs/flutter-apk/app-release.apk`. It uses your local
debug signing key unless you configure a private `android/key.properties` file.
For long-term personal use, configure a stable private key before storing tasks;
CI APKs use temporary signing keys and are intended for testing.

## Attempts and summaries

**Log attempt** records one timestamp at the moment you press it; it is not a
running timer or a duration measurement. Counts are derived from the stored
history, so editing a description does not reset progress. Completed tasks can
still have attempts recorded, and appear in summaries.

Timestamps are stored in UTC and displayed in the device's current local timezone
(to the second). Summary ranges use local calendar dates. Last 7/30 days includes
today; custom ranges include both selected dates. Summaries default to Last 7
days but you can change the period each time. Tasks with no attempts in the range
appear with zero. Deleting a task deletes its history and removes it from summaries;
use Edit for description changes, or mark it completed to preserve its history.

## Storage

`tasks.json` is saved in the platform's application support directory, obtained
through `path_provider`. Tasks are plain text JSON, not encrypted. Local-only data stays on each device. Account data also syncs to Supabase once
you sign in and set up the database. Uninstalling can remove unsynced local changes. Back up this file with the
app closed if you need to preserve it.

Version 0.2 reads existing version-1 task files as tasks with no attempts. On the
first save it preserves the original file as `tasks.json.v1.bak` and writes the
new version-2 format. Older app versions cannot read the new format: keep using
0.2 or newer once you start recording attempts. The legacy backup does not contain
any attempts recorded after upgrading.

Each save flushes a temporary file before replacing the previous file. A process
lock prevents simultaneous app instances from writing over each other. If the
file is unreadable, the app preserves it and displays an error instead of
silently resetting your list. Changes that fail to save do not appear completed.
Account caches and pending changes are saved together in version-3
`account-<user-id>.json` files. Sessions use the OS credential store.

## Personal device sync

Follow the [Supabase setup guide](docs/supabase-setup.md) to run the SQL migration,
create your app account, and import existing local tasks. The supplied project URL
and publishable key are configured in the app; the database password is never
included. Sign into the same account on each device. Other accounts have separate
lists; inviting other users is not supported.

Sync retries offline edits automatically while the app is open. Attempts merge;
conflicting edits to the same field use the last change received by the server.
Task deletion wins over stale edits. Signing out retains that account’s cached
files and unsent changes on this device. See the guide for details and limitations.

## Automation

GitHub Actions runs analysis, persistence/UI tests, and native builds on Linux,
Windows, Android, and macOS (unsigned iOS). Desktop bundles and an Android
test APK are uploaded as workflow artifacts. Platform build success does not replace testing global shortcuts and
iOS behavior on real devices.
