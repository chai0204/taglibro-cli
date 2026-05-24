# taglibro CLI

Terminal client for [taglibro](https://github.com/chai0204/taglibro) —
read and write your own diaries over Supabase, sharing the same Row
Level Security contract the Flutter app uses. Pure-Dart, no Flutter
SDK required.

> Status: **v0.1.1** — full diary CRUD, category management, scripted
> writes, file upload + configurable date parsing, cross-device
> preempt warnings, Linux / macOS arm64 / Windows x64 binaries.

## Install

### Linux / macOS

```sh
curl -fsSL https://raw.githubusercontent.com/chai0204/taglibro-cli/main/install.sh | sh
```

The installer drops the binary at `~/.local/bin/taglibro` and prints
the line to add to your shell rc if the directory isn't already on
`$PATH`. Pass `--yes` to let the installer append automatically:

```sh
curl -fsSL https://raw.githubusercontent.com/chai0204/taglibro-cli/main/install.sh | sh -s -- --yes
```

> **Intel Mac note**: only Apple Silicon (arm64) binaries are built.
> Intel Macs can build from source — see *Build from source* below.

### Windows

```powershell
irm https://raw.githubusercontent.com/chai0204/taglibro-cli/main/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Programs\taglibro\taglibro.exe` and appends
that directory to the User PATH. Open a new PowerShell window to pick
up the change.

### Verify

```sh
taglibro --version
```

## Authentication

```sh
taglibro login
```

Prompts for the email + password of an existing taglibro account
(create one in the Flutter app first), then writes the session to:

- Linux/macOS: `$XDG_CONFIG_HOME/taglibro/credentials.json`
  (`~/.config/taglibro/credentials.json` if `XDG_CONFIG_HOME` is unset),
  mode `0600`.
- Windows: `%APPDATA%\taglibro\credentials.json` — the directory is
  per-user roaming storage that other Windows users can't read.

For scripted / CI use, pipe the password in instead of typing it:

```sh
echo "$MY_PASSWORD" | taglibro login --email me@example.com --password-stdin
```

Sign out (clears credentials + the local preempt-write history):

```sh
taglibro logout
```

## Commands

| Command | Purpose |
|---|---|
| `taglibro list [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--limit N]` | newest-first own-diary list |
| `taglibro show YYYY-MM-DD [--blocks]` | one diary's body |
| `taglibro search "query"` | ILIKE across your own diaries |
| `taglibro export --from ... --to ... [-o file.md]` | period export to markdown |
| `taglibro new [--date YYYY-MM-DD] [--visibility …]` | create today's (or backdated) diary |
| `taglibro edit YYYY-MM-DD` | re-open an existing diary in `$EDITOR` |
| `taglibro rm YYYY-MM-DD [--yes]` | delete with tombstone |
| `taglibro upload <file>... [--date …] [--append \| --overwrite]` | upload markdown files; date from `--date` > filename > today |
| `taglibro date-config show/set/edit` | configure how filenames are parsed for dates (`upload`) |
| `taglibro category list/add/rm/assign/unassign` | manage user categories |
| `taglibro whoami` | show the signed-in account |

Run `taglibro <command> --help` for the full option list.

### Non-interactive writes (for scripts / AI assistants)

`new` and `edit` both accept the body without opening `$EDITOR`:

```sh
# Inline body
taglibro new --date 2026-05-14 --body "# Today

Quick note." --yes

# Pipe a multi-line buffer
cat draft.md | taglibro new --date 2026-05-14 --body-stdin --yes

# Edit an existing diary from a heredoc
taglibro edit 2026-05-14 --body-stdin <<'EOF'
# Updated

New content.
EOF

# Fail loudly when input is missing (no prompts)
taglibro new --body "..." --non-interactive
```

`--yes` skips the empty-body confirmation. `--non-interactive` errors
out instead of prompting — useful in CI where a stray TTY read would
hang the job.

## Uploading existing files

`taglibro upload` takes one or more markdown files and creates (or
updates) a diary per file. Each file's date is resolved in this order:

1. `--date YYYY-MM-DD` (only allowed with a single file or stdin)
2. The first date pattern matched in the file's *basename*, using the
   configured `date_format`
3. Today (UTC) — a stderr note is emitted so silent fallbacks are
   visible

```sh
# Single file, date from filename (ymd-`-` is the default)
taglibro upload 2023-05-24.md

# Multiple files, dates from each filename
taglibro upload journal/*.md

# Override the date for a single file
taglibro upload draft.md --date 2026-05-24

# Pipe a body in, --date is mandatory because there is no filename
cat draft.md | taglibro upload --date 2026-05-24 --append
```

When the target date already has a diary, `upload` defaults to a
confirm prompt that appends the new content after a blank line.
Flags skip the prompt for scripts:

| Flag | Behaviour on existing diary |
|---|---|
| (none, TTY) | Confirm prompt, default-yes → append |
| `--append` | Append silently |
| `--overwrite` | Replace silently — destructive |
| `--yes` | Append (no prompt) |
| `--non-interactive` | Exit 1 unless `--append` or `--overwrite` |

### Configuring filename date parsing

The format that `upload` looks for in filenames is configurable per
user. Defaults to `ymd` + `-` (i.e. `YYYY-MM-DD`).

```sh
taglibro date-config show
# date_format:
#   order:     ymd
#   separator: -
# source: ~/.config/taglibro/config.json

# Switch to `DD.MM.YYYY` for European-style filenames
taglibro date-config set --order dmy --separator .

# Compact `YYYYMMDD` works too
taglibro date-config set --separator none

# Or open the JSON in $EDITOR
taglibro date-config edit
```

Per-invocation overrides skip persistence:

```sh
taglibro upload 24-05-2023-foo.md --date-order dmy --date-separator -
```

Supported separators: `-`, `/`, `.`, `_`, `:`, `none` (compact). `/`
and `:` cannot appear inside real filenames on every OS, so the CLI
warns when they're chosen — they're still useful for explicit
`--date` / stdin invocations.

## Cross-device preempt warnings

When you write a diary from one device (this CLI, the Flutter app on
your phone, etc.) and then another client modifies the same row
later, the next CLI command surfaces a stderr warning so you know
your latest CLI-side state isn't the authority any more:

```
$ taglibro list
! 2026-05-14 was modified by another client after your write
  (server: 2026-05-14T11:00:00Z; your write: 2026-05-14T09:00:00Z).
…
```

The warning is informational — the command still runs. Open the
Flutter app to see what the row looks like now (it has a matching
"上書きされた変更" banner for preempts going the other way).

## Configuration

The CLI bakes the production Supabase URL + anon key into the
binary at build time, so a downloaded release works out of the box.
Override at runtime via environment variables:

| Variable | Effect |
|---|---|
| `SUPABASE_URL` | Override the baked-in URL (e.g. point at a local Supabase). |
| `SUPABASE_ANON_KEY` | Override the baked-in publishable anon key. |
| `EDITOR` / `VISUAL` | Editor binary for `new` / `edit`. |
| `XDG_CONFIG_HOME` | (POSIX) base for the credentials file. |

Why is shipping the anon key safe? It's the *publishable* Supabase
key — already inside the Flutter web bundle and designed to be
public. Row Level Security policies enforce data access; the key
alone gives no privileged read.

## Build from source

```sh
git clone https://github.com/chai0204/taglibro-cli
cd taglibro-cli
fvm dart pub get   # or `dart pub get` if you have a stable Dart SDK
fvm dart compile exe bin/taglibro.dart -o ~/.local/bin/taglibro
```

To bake non-default Supabase credentials at compile time:

```sh
dart compile exe bin/taglibro.dart -o taglibro \
  --define=SUPABASE_URL=https://your-project.supabase.co \
  --define=SUPABASE_ANON_KEY=eyJhbGciOi…
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | User-input error (bad date format, missing required arg) |
| 2 | Not logged in (no credentials file) |
| 3 | Session expired (refresh token rejected) |
| 4 | Resource not found |
| 5 | Server error (Supabase 4xx/5xx) |
| 77 | Smoke test skipped (precondition missing) |
| 99 | Internal / unexpected error |

## License

[MIT](./LICENSE) — see the file for the full text.

## Development

```sh
fvm dart test          # unit tests
fvm dart analyze       # static analysis
tools/smoke_e2e.sh     # end-to-end against a local Supabase
tools/smoke_e2e.ps1    # same, PowerShell port for Windows
```

GitHub Actions builds Linux x64 / macOS arm64 / Windows x64 binaries
on every push tag matching `v*` and attaches them to a Release. See
`.github/workflows/release.yml`.
