// Publishable client configuration. This key is public by design; row-level
// security and authenticated RPCs protect data. NEVER put a DB/service key here.
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://gptkxhsequdqqkkbcswy.supabase.co',
);
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_QMXo8aCKDQQXSE2p7A5WCQ_t68T57nO',
);
