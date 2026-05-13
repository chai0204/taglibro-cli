# taglibro CLI

Terminal client for taglibro. Read / write your own diaries via
Supabase directly, sharing the same RLS and RPC contract as the
Flutter app. Pure-Dart — no Flutter SDK required.

Design rationale lives at `~/life/works/taglibro-cli/design.md`.
Refactor plan for the shared-package extraction (Phase D outcome)
is at `~/life/works/taglibro-cli/refactor-plan.md`.

> ⚠️ **Drift risk — read before editing the Flutter `lib/features/
> editor/domain/` files.** A small set of pure-Dart helpers is
> hand-mirrored into this package because Phase D opted to keep the
> CLI on a copy rather than do an invasive Flutter-side move. See
> the [Mirrored from Flutter](#mirrored-from-flutter) table below
> and run `tools/check_drift.sh` from the repo root after any
> change to the Flutter originals.

## Status

Phases A + B + C shipped — full diary CRUD over Supabase.

| Command | Status |
|---|---|
| `taglibro --version` | ✓ |
| `taglibro --help` | ✓ |
| `taglibro login` | ✓ |
| `taglibro logout` | ✓ |
| `taglibro whoami` | ✓ |
| `taglibro list` | ✓ |
| `taglibro show <date>` | ✓ |
| `taglibro search <q>` | ✓ |
| `taglibro export` | ✓ |
| `taglibro new` | ✓ |
| `taglibro edit <date>` | ✓ |
| `taglibro rm <date>` | ✓ |
| `taglibro category list` | ✓ |
| `taglibro category add <name>` | ✓ |
| `taglibro category rm <id>` | ✓ |
| `taglibro category assign <cat-id> <user-id>` | ✓ |
| `taglibro category unassign <cat-id> <user-id>` | ✓ |

## Install

The CLI ships as a single Dart executable. From the repo:

```bash
cd ~/taglibro/cli
fvm dart pub get
fvm dart compile exe bin/taglibro.dart -o ~/.local/bin/taglibro
```

After that `taglibro` is on `$PATH` (assuming `~/.local/bin` is). If
you'd rather skip compilation during development:

```bash
cd ~/taglibro/cli && fvm dart run bin/taglibro.dart <subcommand>
```

`dart pub get` resolves to the pure-Dart `supabase` client, **not**
`supabase_flutter`, so no Flutter SDK is required to use the
compiled binary.

### Environment variables

| Name | Default | Effect |
|---|---|---|
| `EDITOR` | (none) | Editor binary used by `new` / `edit`. |
| `VISUAL` | (none) | Same role as `EDITOR`, checked second. |
| `XDG_CONFIG_HOME` | `~/.config` | Base for `taglibro/credentials.json`. |
| `SUPABASE_URL` | (file) | Overrides repo-derived URL. |
| `SUPABASE_ANON_KEY` | (file) | Overrides repo-derived anon key. |
| `TAGLIBRO_TEST_EMAIL` | (smoke) | Read by `tools/smoke_e2e.sh`. |
| `TAGLIBRO_TEST_PASSWORD` | (smoke) | 〃 |

The CLI talks to the same Supabase project as the Flutter app. It
locates the URL and anon key in this order:

1. `SUPABASE_URL` and `SUPABASE_ANON_KEY` environment variables.
2. `<repo-root>/config/<env>.json` (the same file the Flutter
   `--dart-define-from-file` flag reads). `<env>` is `prod` by
   default, or `dev` when `--env=dev` is passed.

The anon key is a public Supabase key — it's already baked into
the Flutter web bundle — so reading it from the repo on disk is
not a credential leak.

## Usage

```bash
# One-time interactive login. Stores ~/.config/taglibro/credentials.json
# with mode 0600.
fvm dart run bin/taglibro.dart login

# What account am I signed in as?
fvm dart run bin/taglibro.dart whoami

# Drop the local session (also tries a best-effort server-side
# /logout call).
fvm dart run bin/taglibro.dart logout
```

The `login` command supports a `--dry-run` flag that walks the
email / password prompts without contacting Supabase or saving
credentials — used by smoke checks.

### Read-only commands

```bash
# Latest 20 of your own diaries.
fvm dart run bin/taglibro.dart list

# A specific date, with per-block scope labels.
fvm dart run bin/taglibro.dart show 2026-05-12 --blocks

# Full-text search across your own diaries (ILIKE).
fvm dart run bin/taglibro.dart search "深層学習"

# Period export to a single Markdown file.
fvm dart run bin/taglibro.dart export \
  --from 2026-05-01 --to 2026-05-31 -o may.md
```

`list` / `show` / `search` honour the global `--json` flag for
machine-readable output:

```bash
fvm dart run bin/taglibro.dart --json list --limit 5 | jq
```

Notes on the read path:

- All four commands filter to `auth.uid()` explicitly. RLS on
  `diaries` is `auth.uid() = user_id OR visibility = 'public'`, so
  without that filter `list` would also surface public diaries from
  other users.
- `search` calls the `search_diary_blocks` RPC (`SECURITY INVOKER`,
  RLS applies) and post-filters to your own user_id, over-fetching
  4× the requested limit so the final result still satisfies
  `--limit` after the filter.
- `export` paginates by date in pages of 500 to stay under
  PostgREST's default 1000-row cap; it concatenates diaries
  oldest-first, preserves scope-tagged fences verbatim, and
  separates entries with a `---` rule.

### Write commands

```bash
# Create today's diary; $EDITOR opens on an empty buffer.
fvm dart run bin/taglibro.dart new

# Backdate or pick a visibility.
fvm dart run bin/taglibro.dart new --date 2026-05-12 \
    --visibility=public

# Re-open an existing diary; if you save the file unchanged the
# command exits without touching the server.
fvm dart run bin/taglibro.dart edit 2026-05-12

# Delete; prompts unless --yes is passed. Cascades to blocks /
# reactions / notifications by FK ON DELETE.
fvm dart run bin/taglibro.dart rm 2026-05-12
```

`$EDITOR` resolution order: `$EDITOR` → `$VISUAL` → first available
of `nano` / `vim` / `vi`. The buffer round-trips through a temp
file under `$TMPDIR`; the editor is invoked through `$SHELL -c`
so multi-word editor commands (`emacs -nw`, `code --wait`) work
unchanged.

Scope-tagged fences (`​\`\`\`#public`, `​\`\`\`#connect`,
`​\`\`\`#cat:<uuid>`, `​\`\`\`#private`) inside the body are
recognised by `parseTaggedMarkdown` and turned into per-block
records; the rest of the document inherits `--visibility`. Invalid
category UUIDs are downgraded to `private` server-side by the
RPC — there's no client-side validation, and that's intentional
(see design.md §6).

### Category management

```bash
# Inspect / list
taglibro category list                                 # all yours, alphabetised
taglibro --json category list | jq                     # pipe-friendly

# Create / delete
taglibro category add "Family" --color="#E53935"
taglibro category rm <cat-id>                          # confirms by default
taglibro category rm <cat-id> --yes                    # skip prompt

# Membership
taglibro category assign <cat-id> <user-id>
taglibro category unassign <cat-id> <user-id>
```

`category rm` routes through the `archive_category` RPC, which
downgrades every diary_block referencing the category to `private`
in the same transaction before dropping the category. A plain
`DELETE` would hit the `fk_category_requires_scope` CHECK
constraint and roll back. The downgrade is **destructive in the
scope direction** — once the category is gone, those blocks won't
auto-restore to category-scope; you'd need to edit them
individually.

Category visibility on the read side is enforced by the
`diary_blocks` RLS policy + the `is_viewer_in_category` helper
function. The pinned test suite at
`supabase/tests/category_rls.sql` exercises seven leak / fail-safe
cases including post-membership-removal and post-deletion access.

## Testing

```bash
# Unit tests (no network, no supabase needed).
cd ~/taglibro/cli && fvm dart test

# End-to-end smoke against the *local* Supabase. Requires
# `supabase start` running in the repo + a seeded test user.
TAGLIBRO_TEST_EMAIL=alice@example.com \
TAGLIBRO_TEST_PASSWORD=password123 \
  cli/tools/smoke_e2e.sh

# Drift check (post-Flutter-edit hygiene).
cli/tools/check_drift.sh
```

The smoke script gates on three pre-flight probes:

1. `fvm` on `$PATH`.
2. `http://localhost:19000/rest/v1/` reachable (i.e. `supabase
   start` is up).
3. `TAGLIBRO_TEST_EMAIL` / `TAGLIBRO_TEST_PASSWORD` exported.

Missing any of those → exit 77 (skip) with a clear stderr note.
The script isolates its own credentials into `$XDG_CONFIG_HOME`
under a temp dir and uses a dummy `$EDITOR` so the host shell's
real config / editor aren't disturbed.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Not logged in. Run 'taglibro login' first.` | No `~/.config/taglibro/credentials.json`. | Run `taglibro login`. |
| `Session expired. Run 'taglibro login' to sign in again.` (exit 3) | Refresh token rejected by GoTrue. | Re-run `taglibro login`. |
| `Could not find Supabase config for env="prod".` | Not inside the taglibro repo and no `SUPABASE_URL` / `SUPABASE_ANON_KEY` env vars. | `cd` into the repo, or export the two env vars. |
| `No editor found.` from `new` / `edit`. | `$EDITOR` unset and `nano` / `vim` / `vi` not installed. | `export EDITOR=vim` (or your choice). |
| `Invalid date "<value>"` (exit 1) | Date wasn't `YYYY-MM-DD`. | Use canonical form, e.g. `2026-05-12`. |
| `No diary for 2026-05-12.` (exit 4) | Asked `show` / `edit` / `rm` for a date that doesn't have a diary. | Either pick a different date or create with `new`. |

## Known limitations (v1)

- One diary per (user, date). The schema enforces it; `new` for an
  existing date offers to redispatch to `edit` instead.
- `edit` / `new` always full-replace the block list via
  `upsert_diary_blocks` — the RPC deletes then re-inserts inside
  a single transaction. No partial block updates.
- A `\`\`\`#cat:<uuid>` fence whose category id doesn't belong to
  the signed-in user is silently downgraded to `private` by the
  server-side RPC. This is intentional (leak-prevention) but means
  copying a category-tagged block across users won't preserve
  visibility.
- Public diaries from other users are visible to RLS but
  deliberately filtered out client-side (`list` / `show` / `search`
  always pin to your own user_id).
- Markdown ↔ blocks conversion is a CLI-side regex split — the
  Flutter app uses AppFlowy's richer markdown parser. Heading
  fold state, callouts, and other AppFlowy-specific node types are
  preserved as text but not as structured nodes.
- No offline cache. Every read goes to Supabase.

## Mirrored from Flutter

Phase D shipped on the copy-and-guard route (B-plan in
`design.md` §2): the CLI keeps its own copy of the small
pure-Dart helpers it needs, rather than packages/-extracting them
out of the Flutter app. The trade-off: zero risk to existing
Flutter builds, at the cost of a drift class we have to police.

| CLI copy | Source of truth (Flutter) | What's mirrored |
|---|---|---|
| `cli/lib/src/markdown/block_scope.dart` — `StoredBlock` class | `lib/features/editor/domain/entities/stored_block.dart` | Class shape only — three fields. |
| `cli/lib/src/markdown/block_scope.dart` — `parseTaggedMarkdown`, `_decideScopeFromTags`, `_uuidRe` | `lib/features/editor/domain/block_scope.dart` | The four canonical regions: the parser function, the scope-tag decision helper, the UUID regex constant, and the `_ScopeDecision` value class. |

`computeCharCount` and `extractBody` in the CLI copy are CLI-only
(the Flutter equivalents are AppFlowy-dependent and can't run
headlessly). Drift in those isn't a correctness risk — they only
feed the `body` / `char_count` columns the next Flutter edit
overwrites anyway.

### Detecting drift

```bash
cli/tools/check_drift.sh
```

Extracts the four canonical regions from both files, whitespace-
normalises, and `diff`s them. Exit 0 means in sync, exit 1 prints
the offending diff. Run after every Flutter-side change to
`block_scope.dart` and before each Phase D+ commit. CI hook lands
in Phase E.

### When in doubt

If you change the Flutter parser and the script flags drift, the
right move is almost always to update the CLI copy verbatim to
match — the canonical scope-tag semantics live with the app, not
the CLI. The refactor plan at
`~/life/works/taglibro-cli/refactor-plan.md` enumerates the
candidates for the eventual `packages/taglibro_core/` move that
will retire this whole section.

## Credentials file

Path: `$XDG_CONFIG_HOME/taglibro/credentials.json` when set, else
`~/.config/taglibro/credentials.json`. Mode 0600.

Shape:
```json
{
  "schema_version": 1,
  "supabase_url": "https://…supabase.co",
  "anon_key": "<public anon key>",
  "session": {
    "access_token": "…",
    "refresh_token": "…",
    "expires_at": "2026-05-12T10:00:00.000Z"
  },
  "user": { "id": "<uuid>", "email": "you@example.com" }
}
```

Subsequent commands read this file and proactively refresh when the
access token has under 60 seconds of life left. If the refresh
token has itself expired, the CLI exits with code 3 and asks you to
re-run `taglibro login`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | User-input error (bad date format, missing required prompt, etc.) |
| 2 | Not logged in (no credentials file) |
| 3 | Session expired (refresh token rejected) |
| 4 | Resource not found (Phase B+) |
| 5 | Server error (Supabase 4xx/5xx) |
| 99 | Internal / unexpected error |

## Layout

```
cli/
├── bin/taglibro.dart            ← entry point
├── lib/src/
│   ├── auth/
│   │   ├── auth_service.dart    ← login / refresh / sign-out
│   │   └── credentials_store.dart
│   ├── commands/
│   │   ├── login_command.dart
│   │   ├── logout_command.dart
│   │   └── whoami_command.dart
│   └── util/
│       └── config_resolver.dart ← SUPABASE_URL / anon discovery
├── pubspec.yaml                  ← pure-Dart; depends on `supabase`, not `supabase_flutter`
└── README.md
```

## Why a separate pubspec (not pubspec workspaces yet)

Dart 3.6 supports pubspec workspaces, but Phase A intentionally
keeps the CLI as a stand-alone package so:

- The root Flutter pubspec doesn't change (zero risk to existing
  builds while the CLI is in flux).
- The CLI can pull `supabase` (pure-Dart) without dragging Flutter
  SDK into its resolver.

Phase D will revisit this: extract `lib/features/editor/domain/
entities/` into a `packages/taglibro_core/` workspace member that
both Flutter and CLI share. Until then, when Phase C lands the
markdown↔blocks conversion the CLI may end up with a small copy of
`DiaryEntity` / `StoredBlock` / `parseTaggedMarkdown` to avoid
importing the Flutter package directly.
