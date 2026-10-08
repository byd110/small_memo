import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_store.dart';
import 'secure_session_storage.dart';
import 'task.dart';
import 'task_controller.dart';
import 'task_store.dart';

abstract interface class MemoRemote {
  Future<List<Task>> exchange(String owner, List<MemoOperation> operations);
}

class SupabaseMemoRemote implements MemoRemote {
  SupabaseMemoRemote(this.client);
  final SupabaseClient client;
  @override
  Future<List<Task>> exchange(
    String owner,
    List<MemoOperation> operations,
  ) async {
    var session = client.auth.currentSession;
    if (session == null || session.user.id != owner) {
      throw const AuthException('Account changed');
    }
    if (session.isExpired) {
      await client.auth.refreshSession();
      session = client.auth.currentSession;
    }
    if (session == null || session.user.id != owner) {
      throw const AuthException('Account changed');
    }
    final data = await client
        .rpc(
          'memo_sync',
          params: {'operations': operations.map((o) => o.toJson()).toList()},
        )
        // Pin credentials to this batch, even if the user switches accounts
        // while Supabase's HTTP middleware awaits token refresh.
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .timeout(const Duration(seconds: 20));
    return (data as List).map((item) {
      final json = Map<String, dynamic>.from(item as Map);
      json['attempts'] = (json['attempts'] as List)
          .map(
            (a) => {
              'id': a['id'],
              'at': DateTime.parse(a['at'] as String).toUtc().toIso8601String(),
            },
          )
          .toList();
      return Task.fromJson(json);
    }).toList();
  }
}

/// One request at a time. Edits remain available while the network is pending.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService(
    this.controller,
    this.directory,
    this.client, {
    MemoRemote? remote,
    this.sessionStorage,
  }) : remote = remote ?? SupabaseMemoRemote(client);
  final TaskController controller;
  final Directory directory;
  final SupabaseClient client;
  final MemoRemote remote;
  final SecureSessionStorage? sessionStorage;
  String? get storageWarning => sessionStorage?.warning.value;
  StreamSubscription<AuthState>? _auth;
  Timer? _poll;
  Timer? _debounce;
  Future<void> _authWork = Future.value();
  int _generation = 0;
  bool syncing = false;
  bool switching = false;
  bool _disposed = false;
  String? error;
  DateTime? lastSynced;
  String? get email => client.auth.currentUser?.email;
  SyncTaskStore? get store => controller.store is SyncTaskStore
      ? controller.store as SyncTaskStore
      : null;
  int get pendingCount => store?.pending.length ?? 0;
  String get status {
    if (switching) return 'Opening account…';
    if (store == null) return 'Saved on this device';
    if (error != null || storageWarning != null) {
      return 'Saved locally · sync needs attention';
    }
    if (syncing) return 'Saved locally · syncing…';
    if (pendingCount > 0) {
      return 'Saved locally · $pendingCount pending changes';
    }
    return lastSynced == null
        ? 'Saved locally · waiting to sync'
        : 'Synced across your devices';
  }

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    sessionStorage?.warning.addListener(_changed);
    _auth = client.auth.onAuthStateChange.listen(
      (_) {
        _queueAccount();
      },
      onError: (Object _) {
        error =
            'Sign-in could not refresh. Your changes remain saved locally. Try signing in again.';
        notifyListeners();
      },
    );
    await _queueAccount();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => sync());
  }

  Future<void> _queueAccount() {
    final owner = client.auth.currentUser?.id;
    _authWork = _authWork.then((_) async {
      if (_disposed) return;
      if (store?.owner == owner &&
          (owner != null || controller.store is! SyncTaskStore)) {
        return;
      }
      _generation++;
      switching = true;
      lastSynced = null;
      error = null;
      notifyListeners();
      // Let an already-started disk write finish before closing its file lock.
      while (controller.busy && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (_disposed) return;
      try {
        final next = owner == null
            ? FileTaskStore(File('${directory.path}/tasks.json'))
            : SyncTaskStore(
                File('${directory.path}/account-$owner.json'),
                owner,
              );
        await controller.changeStore(next);
      } catch (_) {
        error = 'Could not open this account’s saved data. Restart to retry.';
      } finally {
        switching = false;
        notifyListeners();
      }
      unawaited(sync());
    });
    return _authWork;
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    if (!controller.busy && !switching && pendingCount > 0) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), sync);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  Future<void> sync() async {
    final target = store;
    if (_disposed ||
        syncing ||
        switching ||
        !controller.ready ||
        target == null ||
        client.auth.currentUser?.id != target.owner) {
      return;
    }
    final generation = _generation;
    syncing = true;
    error = null;
    notifyListeners();
    try {
      do {
        final batch = target.pending.take(100).toList();
        final snapshot = await remote.exchange(target.owner, batch);
        if (_disposed ||
            generation != _generation ||
            target != store ||
            client.auth.currentUser?.id != target.owner) {
          return;
        }
        final committed = await controller.applyExternal(
          () => target.merge(snapshot, batch.map((o) => o.id).toSet()),
        );
        if (!committed) {
          return; // Retry the same operation IDs on the next pass.
        }
        lastSynced = DateTime.now();
      } while (target.pending.isNotEmpty && generation == _generation);
    } on PostgrestException catch (e) {
      if (generation != _generation || _disposed) return;
      error = e.code == 'PGRST202' || e.code == '42P01'
          ? 'Database setup is needed. Run the Small Memo SQL migration in Supabase, then tap Sync now.'
          : 'Sync was rejected. Check your account and database setup, then retry. Local changes are safe.';
    } on AuthException catch (_) {
      if (generation != _generation || _disposed) return;
      error =
          'Please sign in again. Your pending changes remain on this device.';
    } catch (_) {
      if (generation != _generation || _disposed) return;
      error =
          'Could not sync. Check your connection and try again. Local changes are safe.';
    } finally {
      syncing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await _queueAccount();
  }

  Future<bool> signUp(String email, String password) async {
    final result = await client.auth.signUp(
      email: email.trim(),
      password: password,
    );
    await _queueAccount();
    return result.session != null;
  }

  Future<void> signOut() async {
    // Do not report a successful sign-out if the persisted session cannot clear.
    await sessionStorage?.removePersistedSession();
    await client.auth.signOut(scope: SignOutScope.local);
    await _queueAccount();
  }

  Future<void> importLocal() async {
    final target = store;
    if (target == null || switching || target.imported) return;
    final local = FileTaskStore(File('${directory.path}/tasks.json'));
    try {
      final tasks = await local.load();
      if (target != store || switching) return;
      await controller.applyExternal(() => target.importLocal(tasks));
    } catch (_) {
      error =
          'Could not import the local list. The original file is unchanged.';
      notifyListeners();
    } finally {
      await local.close();
    }
    unawaited(sync());
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _auth?.cancel();
    _poll?.cancel();
    _debounce?.cancel();
    controller.removeListener(_changed);
    sessionStorage?.warning.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
