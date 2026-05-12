#!/usr/bin/env bash
# check_drift.sh — verify the canonical scope-tag parser is identical
# between the Flutter and CLI copies.
#
# Phase D (B-route) ships `parseTaggedMarkdown` + its helpers as a
# hand-mirrored copy on the CLI side. There's no compile-time check
# linking the two files, so every PR that touches the Flutter
# original should run this script. The CI hook is deferred to
# Phase E; for now it's a manual check.
#
# Exit codes:
#   0  copies are in sync
#   1  drift detected (diff printed to stderr)
#   2  one of the source files is missing

set -euo pipefail

repo_root() {
  # tools/ lives one level under cli/, which is one level under the
  # repo. Resolve robustly so the script works from any CWD.
  cd "$(dirname "$0")/../.." && pwd
}

REPO="$(repo_root)"
FLUTTER_SRC="$REPO/lib/features/editor/domain/block_scope.dart"
CLI_SRC="$REPO/cli/lib/src/markdown/block_scope.dart"

if [ ! -f "$FLUTTER_SRC" ]; then
  echo "missing canonical source: $FLUTTER_SRC" >&2
  exit 2
fi
if [ ! -f "$CLI_SRC" ]; then
  echo "missing CLI copy:        $CLI_SRC" >&2
  exit 2
fi

# Pull the four pieces of scope-tag logic that have to stay in sync
# from either file. Whitespace runs are normalised to single spaces
# so trivial reformatting doesn't flag drift.
extract() {
  awk '
    /^List<StoredBlock> parseTaggedMarkdown\(/,/^}/ { print }
    /^class _ScopeDecision /,/^}/ { print }
    /^final RegExp _uuidRe /,/;$/ { print }
    /^_ScopeDecision _decideScopeFromTags\(/,/^}/ { print }
  ' "$1" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'
}

flutter_canonical="$(extract "$FLUTTER_SRC")"
cli_copy="$(extract "$CLI_SRC")"

if [ "$flutter_canonical" = "$cli_copy" ]; then
  echo "✓ block_scope.dart in sync"
  exit 0
fi

{
  echo "✗ drift detected between Flutter and CLI copies of block_scope.dart"
  echo "  canonical: $FLUTTER_SRC"
  echo "  cli copy:  $CLI_SRC"
  echo
  echo "  Diff (normalised, canonical → cli):"
  diff <(extract "$FLUTTER_SRC") <(extract "$CLI_SRC") || true
} >&2
exit 1
