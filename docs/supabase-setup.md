# Set up personal device sync

Small Memo 0.3 adds optional email/password accounts. Sign into **the same account**
on Windows, Linux, iPhone, and Android to use one list. Different accounts have
separate lists; there are no invitations or shared lists in this version.

## 1. Create the database objects

Open your [Supabase project](https://supabase.com/dashboard/project/gptkxhsequdqqkkbcswy)
and choose **SQL Editor → New query**. Paste the entire contents of
[`202610070001_personal_sync.sql`](../supabase/migrations/202610070001_personal_sync.sql)
and click **Run** once. The transaction creates three tables and a `memo_sync`
function. Do not run `supabase/tests` files in your project: those create mock
Auth objects for an isolated test database only.

The migration enables row-level security. Only signed-in users can call the sync
function; it derives ownership from their verified session, never a client-supplied
account ID. Direct client writes to the tables are denied. The publishable key
alone cannot read tasks or call sync. Project administrators retain database access.

## 2. Create your app account

For this personal project, the easiest setup is **Authentication → Users → Add
user → Create new user** in Supabase. Enter the email and password you want to use
for Small Memo, with **Auto Confirm User** enabled. This is a separate app login,
not your Supabase dashboard login or database password. Do not send that password
in chat or put it in the repository.

Alternatively, the app's **Create account** button uses Supabase email sign-up.
If email confirmation is enabled, confirm the email before signing in. Supabase's
built-in email sender restricts recipients and rate limits; configure custom SMTP
if you need to send to other addresses. The app does not need email deep links:
return to it and sign in after confirmation. Configure your project's Auth Site URL
if you want confirmation links to redirect to a working web page.

For personal-only use, you can turn off **Allow new users to sign up** in Supabase
Auth settings after creating your account. The Create account button will then
report the server's rejection; existing accounts can still sign in. If you forget
your password, manage the account through your Supabase dashboard; in-app password
recovery and account deletion are not included in this release.

## 3. Sign in and bring over existing tasks

1. Install the new app build. Open the person icon (**Account & sync**) and sign in.
2. Choose **Import this device’s local list** if this device has existing tasks.
   Confirm the destination account. Descriptions, completion, and attempt timestamps
   are preserved. The original local-only list remains as a separate copy.
3. Wait for a successful sync. On another device, sign in with the **same email and
   password**. Tap **Sync now** to check immediately.

Import can run once per account per device. It adds new tasks and missing attempts for existing task IDs, preserving the
account’s current descriptions and completion. Copies of the same task IDs merge
on the server; independently
created tasks with the same description remain separate. To avoid re-importing
old work, normal account switching never imports anything automatically.

## Offline use and conflicts

- Every edit saves locally first, including its pending sync command. Closing the
  app or losing the network does not discard pending changes.
- Sync runs shortly after edits, every 30 seconds while the app is running, and
  when it resumes. **Sync now** gives an immediate retry. There is no background
  service when the app is closed or suspended by the OS.
- Attempts from multiple devices combine using unique IDs. Retry requests cannot
  duplicate attempts, and removing an attempt is propagated to other devices.
- Description and completion edits are independent. If two devices edit the same
  field while offline, the last change **received by the server** wins. Device
  clocks do not determine the winner.
- Task deletion wins over stale edits and imports. Deletion records remain on the
  server to stop disconnected devices from recreating removed tasks. Deleted tasks
  disappear from history and summaries; completion preserves them.
- Sign-out affects this device only. Unsynced changes and its cached account list
  stay on disk, hidden from other app accounts, until you sign back in. Signing out
  does not erase files. Tasks remain plain local JSON, so this is not protection
  against someone who can read your OS user profile.

## Configuration and local files

The provided project URL and **publishable** key are in `lib/supabase_config.dart`,
so CI builds work without developer tools. These are public client configuration.
A fork can override them with `--dart-define=SUPABASE_URL=...` and
`--dart-define=SUPABASE_PUBLISHABLE_KEY=...` at build time. Never use a database
password, secret API key, or `service_role` key in the client.

The project owner's database password is stored only in `.env.supabase.local`,
ignored by Git and restricted to its local owner. It is for administration, not
app authentication. Flutter does not load or bundle that file.

The local-only list remains `tasks.json` (version 2). Account files are
`account-<user-id>.json` (version 3), containing the task cache and durable upload
queue in one atomic write. Keep a backup with the app closed before changing or
reinstalling it. An older version of Small Memo cannot display account files.

Sign-in sessions are stored using the OS credential store, separately from tasks:
iOS Keychain, Android secure storage, Windows protected storage, and Linux Secret
Service. Linux needs `libsecret-1-0` and a working unlocked keyring (for example
GNOME Keyring). If credential storage cannot initialize, the app keeps local use
available and displays a sync notice. iOS's Runner target includes the Keychain
entitlements used by the secure-storage plugin; keep these when configuring signing.

## Validation and troubleshooting

- **Database setup is needed**: run the migration above, then Sync now.
- **Email not confirmed**: confirm the email or use the dashboard to create your
  personal account with Auto Confirm enabled.
- **Sync needs attention**: open Account & sync for details. Pending changes are
  retained until a successful retry. Check the network and project availability.
- This release was tested with a disposable PostgreSQL database and simulated
  network failures. After applying the migration, verify with two devices: create
  a task on one, log an attempt on each, edit offline, reconnect, then check that
  both show the same history. The live project must be set up before this test.

The database tests under `supabase/tests` run in CI on PostgreSQL 17 and cover RLS,
account isolation, atomic batches, duplicate retries, field merges, attempt
removal, deletion precedence, and anonymous access denial.

References: [Supabase Flutter initialization](https://supabase.com/docs/reference/dart/initializing),
[row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security),
[email delivery](https://supabase.com/docs/guides/auth/auth-smtp).
