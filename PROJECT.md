# Small Memo scope

The owner chose native apps for iOS, Android, Windows, and Linux, starting **local-only**.
The first version is a single task list with creation, checking/unchecking,
deleting, timestamped attempts, history-preserving editing, selectable date-range
summaries, local persistence, and quick desktop access. No reminders or other
productivity features are planned.

Implementation: Flutter with separate task model, persistence, controller, and UI.
Sync remains a future decision; the current app has no account or backend.

Repository: https://github.com/byd110/small_memo

See README.md for setup, shortcuts, platform limitations, and future sync costs.
