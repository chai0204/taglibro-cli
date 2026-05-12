# taglibro CLI changelog

Versioning: semver-ish. Pre-1.0 anything goes; from 1.0 on, public
behaviour (command syntax, exit codes, credentials file shape) is
the contract — anything that changes them bumps minor or major.

## [1.0.0] — 2026-05-12

First friends-only release. Closes the full diary CRUD loop over
Supabase from the terminal, sharing RLS and RPC contracts with the
Flutter app at `~/taglibro/`.

### Added

- **Auth** (Phase A, commit `8b1df57`)
  - `taglibro login` — interactive email/password, stores session
    at `$XDG_CONFIG_HOME/taglibro/credentials.json` (mode 0600).
  - `taglibro logout` — best-effort server-side `signOut` then
    deletes the local file.
  - `taglibro whoami` — local-only read; exit 2 when not signed in.
  - `--version`, `--help`, `--env={prod,dev}` global flags.
  - `--dry-run` on `login` for headless smoke runs.
  - `~/.config/taglibro/credentials.json` schema v1:
    `{schema_version, supabase_url, anon_key,
    session: {access_token, refresh_token, expires_at},
    user: {id, email?}}`.
  - Proactive refresh: if `access_token` has under 60 s of life,
    `setSession(refresh_token)` is called before the next request.

- **Read** (Phase B, commit `40b1451`)
  - `taglibro list [--from --to --limit]` — newest-first list of
    your own diaries.
  - `taglibro show YYYY-MM-DD [--blocks]` — single diary, optionally
    rendered block-by-block with scope labels.
  - `taglibro search "<query>" [--limit N]` — ILIKE search via
    `search_diary_blocks` RPC, post-filtered to your user_id.
  - `taglibro export --from --to (-o path.md | --stdout)` — period
    export to a single Markdown doc, oldest-first, with `---`
    separators. Paginates by date at 500 rows / page to stay under
    PostgREST's 1000-row cap.
  - `--json` global flag (`list` / `show` / `search`).

- **Write** (Phase C, commit `c16b7a0`)
  - `taglibro new [--date YYYY-MM-DD] [--visibility=…]` — opens
    `$EDITOR` on an empty buffer, parses the result via
    `parseTaggedMarkdown`, upserts `diaries` on `(user_id, date)`,
    then calls `upsert_diary_blocks` to replace the block list.
    Dispatches to `edit` when the date is already taken.
  - `taglibro edit YYYY-MM-DD` — reload + edit. Detects "no-op
    save" by comparing pre/post buffers and short-circuits without
    touching the server.
  - `taglibro rm YYYY-MM-DD [--yes]` — confirmation by default.
    Cascades to `diary_blocks` / `reactions` / `notifications` via
    existing `ON DELETE CASCADE` FKs.
  - `$EDITOR` / `$VISUAL` resolution with `nano → vim → vi`
    fallback; invocation through `$SHELL -c` so editors with
    arguments (`emacs -nw`, `code --wait`) work; `Process.start` +
    `inheritStdio` so TUI editors get a real TTY.

- **Housekeeping** (Phase D, commit `2f01841`)
  - `cli/tools/check_drift.sh` — diff the four canonical regions
    of `parseTaggedMarkdown` between Flutter and the CLI copy.
  - Top-of-README admonition, "Mirrored from Flutter" table, and
    a matching note in the Flutter repo's `CLAUDE.md`.
  - `~/life/works/taglibro-cli/refactor-plan.md` documents the
    eventual `packages/taglibro_core/` extraction path.

- **Tests + smoke** (Phase E, this release)
  - 30 unit tests under `cli/test/`:
    - `markdown/block_scope_test.dart` — `parseTaggedMarkdown`
      coverage including all four tag families, the
      `#cat:<bad-uuid>` private-downgrade safety check, the
      unclosed-fence fallback, plus `computeCharCount` /
      `extractBody`.
    - `util/date_arg_test.dart` — canonical / partial / out-of-
      range YYYY-MM-DD handling.
    - `util/config_resolver_test.dart` — env var override,
      repo-config fallback, env-specific URL switching, missing-
      everything → `StateError`.
    - `auth/credentials_store_test.dart` — save / load round trip,
      mode 0600 verification via `stat -c %a`, idempotent delete,
      `overridePath` precedence.
  - `cli/tools/smoke_e2e.sh` — 11-step end-to-end walk against the
    local Supabase. Probes prerequisites and exits 77 (skip) with
    a clear note when fvm / supabase / test credentials are
    missing. Uses a dummy `$EDITOR` and an isolated
    `XDG_CONFIG_HOME` so host config isn't disturbed.

### Behaviour pinned by these tests (i.e. don't break post-1.0)

- Exit codes: 0 success / 1 user input / 2 not logged in /
  3 session expired / 4 resource not found / 5 server error /
  99 unexpected.
- `parseTaggedMarkdown` priority: `#public` > `#connect|connected`
  > `#cat:<uuid>` > `#private` > base scope.
- `#cat:` with a malformed UUID downgrades to `private`.
- `auth.uid()` filter is applied client-side for `list` / `show` /
  `export` / `search`; RLS alone would also surface other users'
  public diaries.
- Credentials file is mode 0600.
- `dart pub get` resolves to `supabase: ^2.10.0` (NOT
  `supabase_flutter`).

### Known limitations carried into 1.0

- Full block-list replace per edit (no diff-based partial updates).
- No offline cache.
- Markdown↔blocks split is a regex pass, not the AppFlowy parser.
- Drift between `lib/features/editor/domain/block_scope.dart` and
  `cli/lib/src/markdown/block_scope.dart` is policed by a manual
  script rather than a shared package. The refactor plan calls out
  what would trigger the move.
