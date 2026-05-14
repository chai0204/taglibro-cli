/// Compile-time Supabase connection target for distributed binaries.
///
/// `dart compile exe` resolves `String.fromEnvironment` once at build
/// time, so a CI build that does
///
/// ```
/// dart compile exe bin/taglibro.dart \
///   --define=SUPABASE_URL=... \
///   --define=SUPABASE_ANON_KEY=...
/// ```
///
/// bakes the values straight into the final executable. End users get
/// a single binary that already knows where to connect — no config file
/// shipping, no first-run wizard.
///
/// The `defaultValue:` below is the production Supabase project, copied
/// from `taglibro/config/prod.json` at the time of writing. It lets a
/// developer run `dart run bin/taglibro.dart` from source without any
/// `--define` flags and still talk to the same backend the released
/// binary does.
///
/// Why is it safe to bake the anon key?
///   The anon key is the *publishable* Supabase key — the Flutter web
///   build already ships it inside the JS bundle, and Supabase
///   designed it to be public. Row-Level Security (RLS) policies are
///   what actually protect data; the key alone gives no privileged
///   access. Service-role keys must NEVER be baked into this file.
library;

const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://wminhrsclrdwcyuexqac.supabase.co',
);

const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndtaW5ocnNjbHJkd2N5dWV4cWFjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ0NjYxMDcsImV4cCI6MjA4MDA0MjEwN30.3PuYhlRyaOGjXNPzSmcmtWFdPKeRJktyyN0y98bF3Mo',
);
