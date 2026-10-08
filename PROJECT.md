# Small Memo scope

The owner chose native apps for iOS, Android, Windows, and Linux, starting **local-only**.
The first version is a single task list with creation, checking/unchecking,
deleting, timestamped attempts, history-preserving editing, selectable date-range
summaries, local persistence, and quick desktop access. No reminders or other
productivity features are planned.

Implementation: Flutter with separate task model, persistence, controller, and UI.
Version 0.3 adds optional Supabase email/password sign-in and personal device sync,
with offline queues, account-isolated caches, and timestamped attempts that merge.
The same account is used across devices; shared lists/invitations are out of scope.
See docs/supabase-setup.md for the database migration and setup steps.

Repository: https://github.com/byd110/small_memo

See README.md for setup, shortcuts, platform limitations, and sync setup.
