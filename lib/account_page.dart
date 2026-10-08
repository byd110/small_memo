import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_service.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.sync});
  final SyncService sync;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _working = false;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _authenticate({bool create = false}) async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _message = 'Enter your email address and password.');
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      if (create) {
        final signedIn = await widget.sync.signUp(_email.text, _password.text);
        if (mounted && !signedIn) {
          setState(
            () => _message =
                'Check your email to confirm your account, then return here and sign in.',
          );
        }
      } else {
        await widget.sync.signIn(_email.text, _password.text);
      }
      _password.clear();
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not reach sign-in. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out on this device?'),
        content: Text(
          widget.sync.pendingCount > 0
              ? 'Some changes have not synced. They will stay on this device and upload when you sign back into this account. The local-only list will be shown.'
              : 'Your account’s cached list stays on this device. Signing back into the same account restores it. The local-only list will be shown.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await widget.sync.signOut();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not sign out. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy your local list to this account?'),
        content: Text(
          'Tasks and attempts from this device’s local-only list will be uploaded to ${widget.sync.email}. The original local list is kept as a separate copy. This can be done once per account on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Copy tasks'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await widget.sync.importLocal();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account & sync')),
    body: ListenableBuilder(
      listenable: widget.sync,
      builder: (context, _) {
        final sync = widget.sync;
        final signedIn = sync.email != null;
        final disabled = _working || sync.switching || sync.controller.busy;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Use the same account on every device. Only you can access your list through the app.',
                ),
                const SizedBox(height: 20),
                if (signedIn) ...[
                  SelectableText(
                    sync.email!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(sync.status),
                  if (sync.lastSynced != null)
                    Text(
                      'Last synced: ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(sync.lastSynced!))}',
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: disabled || sync.syncing ? null : sync.sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                  if (sync.store != null && !sync.store!.imported)
                    OutlinedButton(
                      onPressed: disabled ? null : _import,
                      child: const Text('Import this device’s local list'),
                    ),
                  TextButton(
                    onPressed: disabled ? null : _signOut,
                    child: const Text('Sign out'),
                  ),
                  const Text(
                    'Offline changes upload automatically when the app is open and connected. Other devices are checked every 30 seconds and when you return to the app.',
                  ),
                ] else ...[
                  TextField(
                    controller: _email,
                    enabled: !disabled,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !disabled,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: disabled ? null : (_) => _authenticate(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: disabled ? null : _authenticate,
                    child: const Text('Sign in'),
                  ),
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () => _authenticate(create: true),
                    child: const Text('Create account'),
                  ),
                  const Text(
                    'You can keep using the local list without signing in. After signing in, you can choose to import it.',
                  ),
                ],
                if (_working || sync.switching) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_message!),
                  ),
                if (sync.storageWarning != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(sync.storageWarning!),
                  ),
                if (sync.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      sync.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
