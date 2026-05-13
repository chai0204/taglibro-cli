#!/usr/bin/env bash
# smoke_e2e.sh — drive the CLI end-to-end against the local Supabase
# (`supabase start` inside ~/taglibro). Walks every shipping command
# at least once, asserts the round-trip is consistent, then cleans
# up after itself.
#
# Required environment:
#   TAGLIBRO_TEST_EMAIL       email of a pre-existing local supabase
#                             test user (seed_dev.sql usually adds
#                             alice@example.com).
#   TAGLIBRO_TEST_PASSWORD    password for that user.
#
# Optional:
#   TAGLIBRO_E2E_KEEP=1       leave the inserted test diary in place
#                             instead of deleting it at the end.
#                             Useful when poking at a failure.
#
# Exit codes:
#   0   all steps passed
#   1   a step failed (which step is printed to stderr)
#   77  local supabase not running → skipped

set -uo pipefail

CLI_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DATE="2099-01-01"
TEST_KEYWORD="TaglibroSmokeKeyword"

skip() {
  echo "[skip] $1" >&2
  exit 77
}
fail() {
  echo "[fail] $1" >&2
  exit 1
}
step() {
  echo "[step] $1" >&2
}

# ── Pre-flight ────────────────────────────────────────────────────

if ! command -v fvm >/dev/null 2>&1; then
  skip "fvm not on PATH"
fi

# Probe the local supabase REST endpoint. Three-second cap so this
# stays fast when the stack isn't running.
if ! curl -fsS -m 3 -o /dev/null http://localhost:19000/rest/v1/ 2>/dev/null; then
  skip "local Supabase not reachable at http://localhost:19000 — run \`supabase start\`"
fi

if [ -z "${TAGLIBRO_TEST_EMAIL:-}" ] || [ -z "${TAGLIBRO_TEST_PASSWORD:-}" ]; then
  skip "TAGLIBRO_TEST_EMAIL / TAGLIBRO_TEST_PASSWORD not set"
fi

# Isolate credentials + editor side-effects to a temp dir.
WORKDIR="$(mktemp -d -t taglibro-e2e-XXXXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
export XDG_CONFIG_HOME="$WORKDIR/xdg"

# Dummy editor that pipes a fixed file in. We use $TAGLIBRO_E2E_SEED
# as the source-of-truth body; the script sets it per call.
mkdir -p "$WORKDIR/bin"
cat >"$WORKDIR/bin/dummy_editor" <<'EOF'
#!/usr/bin/env bash
# arg 1 is the temp file the CLI created.
cat "$TAGLIBRO_E2E_SEED" >"$1"
EOF
chmod +x "$WORKDIR/bin/dummy_editor"
export EDITOR="$WORKDIR/bin/dummy_editor"
export VISUAL="$WORKDIR/bin/dummy_editor"

cli() {
  (cd "$CLI_DIR" && fvm dart run bin/taglibro.dart --env=dev "$@")
}

# ── Steps ────────────────────────────────────────────────────────

step "1/11 login (--dry-run rejected → real login)"
# Pipe email + password on stdin. Login disables echo only on a real
# TTY; stdin pipe goes through the non-TTY branch and reads happily.
printf '%s\n%s\n' "$TAGLIBRO_TEST_EMAIL" "$TAGLIBRO_TEST_PASSWORD" \
  | cli login >/dev/null || fail "login"

step "2/11 whoami"
who="$(cli whoami)" || fail "whoami"
case "$who" in
  *"$TAGLIBRO_TEST_EMAIL"*) ;;
  *) fail "whoami did not echo the test email (got: $who)";;
esac

step "3/11 list (test date should not yet exist)"
if cli list --from "$TEST_DATE" --to "$TEST_DATE" --limit 1 \
     | grep -q "$TEST_DATE"; then
  fail "list already shows $TEST_DATE — stale fixture?"
fi

step "4/11 new (dummy editor seeds the body)"
SEED_NEW="$WORKDIR/seed-new.md"
printf '# Smoke title\n\n%s in the body.\n' "$TEST_KEYWORD" >"$SEED_NEW"
TAGLIBRO_E2E_SEED="$SEED_NEW" cli new --date "$TEST_DATE" \
  >/dev/null || fail "new"

step "5/11 list now includes the test date"
cli list --from "$TEST_DATE" --to "$TEST_DATE" | grep -q "$TEST_DATE" \
  || fail "list missing $TEST_DATE after new"

step "6/11 show round-trips the body"
cli show "$TEST_DATE" | grep -q "$TEST_KEYWORD" \
  || fail "show didn't return the seeded body"

step "7/11 search finds the keyword"
cli search "$TEST_KEYWORD" | grep -q "$TEST_DATE" \
  || fail "search didn't locate the test diary"

step "8/11 export --stdout includes the body"
cli export --from "$TEST_DATE" --to "$TEST_DATE" --stdout \
  | grep -q "$TEST_KEYWORD" || fail "export stdout missing body"

step "9/11 edit replaces the body"
SEED_EDIT="$WORKDIR/seed-edit.md"
printf '# Updated\n\n%s revised.\n' "$TEST_KEYWORD" >"$SEED_EDIT"
TAGLIBRO_E2E_SEED="$SEED_EDIT" cli edit "$TEST_DATE" \
  >/dev/null || fail "edit"
cli show "$TEST_DATE" | grep -q "revised" || fail "edit didn't take effect"

step "10/12 rm (skipped via TAGLIBRO_E2E_KEEP=1)"
if [ "${TAGLIBRO_E2E_KEEP:-0}" = "1" ]; then
  echo "[info] kept $TEST_DATE in place per TAGLIBRO_E2E_KEEP=1" >&2
else
  cli rm "$TEST_DATE" --yes >/dev/null || fail "rm"
  if cli list --from "$TEST_DATE" --to "$TEST_DATE" | grep -q "$TEST_DATE"; then
    fail "rm reported success but list still shows $TEST_DATE"
  fi
fi

step "11/12 re-login + list — tombstoned diary stays gone"
# Forces the access_token + refresh_token round-trip we shipped in
# audit H1, and verifies the rm/list bug Option 2 path: after a
# fresh sign-in the just-deleted diary must NOT come back. A
# regression here would mean the tombstone migration didn't take
# effect or the CLI rm reverted to a plain DELETE.
if [ "${TAGLIBRO_E2E_KEEP:-0}" != "1" ]; then
  cli logout >/dev/null || fail "logout (pre-relogin)"
  printf '%s\n%s\n' "$TAGLIBRO_TEST_EMAIL" "$TAGLIBRO_TEST_PASSWORD" \
    | cli login >/dev/null || fail "login (re-login)"
  if cli list --from "$TEST_DATE" --to "$TEST_DATE" | grep -q "$TEST_DATE"; then
    fail "$TEST_DATE reappeared after re-login (tombstone not honoured?)"
  fi
fi

step "12/12 logout clears credentials"
cli logout >/dev/null || fail "logout"
if [ -f "$XDG_CONFIG_HOME/taglibro/credentials.json" ]; then
  fail "logout did not remove credentials file"
fi

echo "[ok] all 12 steps passed"
