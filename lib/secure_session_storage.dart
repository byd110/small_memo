import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Refresh tokens use the OS credential store, never tasks.json or the repo.
class SecureSessionStorage extends LocalStorage {
  static const _storage = FlutterSecureStorage();
  static const _key = 'small_memo_supabase_session_v1';
  final warning = ValueNotifier<String?>(null);
  Future<void> _writes = Future.value();
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);
  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  // Auth emits persistence events without awaiting them. Serialize writes and
  // deletion so an older token refresh cannot overwrite a newer sign-out.
  Future<void> _write(Future<void> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>(
      (_) {
        warning.value = null;
      },
      onError: (Object _) {
        warning.value =
            'Could not update saved sign-in. Unlock your OS credential store and try again before closing the app.';
      },
    );
    return result;
  }

  @override
  Future<void> persistSession(String persistSessionString) =>
      _write(() => _storage.write(key: _key, value: persistSessionString));
  @override
  Future<void> removePersistedSession() =>
      _write(() => _storage.delete(key: _key));
}
