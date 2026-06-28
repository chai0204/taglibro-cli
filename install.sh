#!/usr/bin/env sh
# Taglibro CLI installer for Linux + macOS.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/chai0204/taglibro-cli/main/install.sh | sh
#
# What it does:
#   1. Detect the host OS + architecture.
#   2. Fetch the latest GitHub Release asset URL via the public REST API.
#   3. Download the binary to ~/.local/bin/tgl (chmod +x).
#   4. If ~/.local/bin isn't on $PATH, suggest the right shell rc line to add.
#   5. Verify with `tgl --version` and print next-step instructions.
#
# Flags:
#   --yes        Don't prompt for the PATH append; just print the line.
#   --dry-run    Walk the steps without downloading or writing anything.
#   --help       This text.
#
# Exit codes:
#   0  ok
#   1  usage / unsupported platform
#   2  download or write failure
#   3  binary smoke (`--version`) failed

set -eu

REPO="chai0204/taglibro-cli"
INSTALL_DIR="${HOME}/.local/bin"
BIN_NAME="tgl"
YES=0
DRY_RUN=0

usage() {
  sed -n '2,21p' "$0"
}

# ── arg parse ──────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown flag: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

# ── platform detection ────────────────────────────────────────────
uname_s=$(uname -s)
uname_m=$(uname -m)
case "${uname_s}" in
  Linux)
    case "${uname_m}" in
      x86_64|amd64) ASSET="taglibro-linux-x64" ;;
      *)
        echo "✗ Unsupported Linux architecture: ${uname_m}" >&2
        echo "  Only x86_64 is built. File an issue if you need others." >&2
        exit 1
        ;;
    esac
    ;;
  Darwin)
    case "${uname_m}" in
      arm64) ASSET="taglibro-macos-arm64" ;;
      x86_64)
        echo "✗ Intel Mac (x86_64) is not supported in v0.1.0." >&2
        echo "  Only Apple Silicon (arm64) binaries are built." >&2
        echo "  If you have Rosetta installed, the arm64 binary will run via" >&2
        echo "  emulation — pass --force-arm64 (not implemented yet) or" >&2
        echo "  build from source: https://github.com/${REPO}#build-from-source" >&2
        exit 1
        ;;
      *)
        echo "✗ Unsupported macOS architecture: ${uname_m}" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "✗ Unsupported OS: ${uname_s}" >&2
    echo "  Linux / macOS are supported. Windows users: install.ps1." >&2
    exit 1
    ;;
esac

echo "→ Detected ${uname_s}/${uname_m} → asset: ${ASSET}"

# ── tool checks ────────────────────────────────────────────────────
need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "✗ '$1' is required but not installed." >&2
    exit 1
  }
}
need curl
need uname

# ── fetch latest release metadata ──────────────────────────────────
API="https://api.github.com/repos/${REPO}/releases/latest"
echo "→ Querying ${API}"
RELEASE_JSON=$(curl -fsSL "${API}") || {
  echo "✗ Failed to query GitHub Releases API." >&2
  exit 2
}

# Pull `tag_name` and the asset's `browser_download_url` without jq:
# the JSON is structured enough that grep + sed suffice. Falls back
# to a louder error if either is missing so a silent rename of the
# asset doesn't ship a broken installer.
TAG=$(printf '%s' "${RELEASE_JSON}" | grep -m1 '"tag_name"' \
  | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
ASSET_URL=$(printf '%s' "${RELEASE_JSON}" \
  | grep -E '"browser_download_url".*'"${ASSET}"'"' \
  | head -1 \
  | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')

if [ -z "${TAG}" ] || [ -z "${ASSET_URL}" ]; then
  echo "✗ Could not find asset '${ASSET}' in the latest release." >&2
  echo "  Tag parsed: '${TAG}'" >&2
  echo "  Open ${API} to check what was actually published." >&2
  exit 2
fi

echo "→ Latest release: ${TAG}"
echo "→ Asset URL:      ${ASSET_URL}"

# ── download + install ────────────────────────────────────────────
if [ "${DRY_RUN}" = "1" ]; then
  echo "[dry-run] would download to ${INSTALL_DIR}/${BIN_NAME}"
  echo "[dry-run] would chmod +x"
  echo "[dry-run] skipping PATH check"
  exit 0
fi

mkdir -p "${INSTALL_DIR}"
TARGET="${INSTALL_DIR}/${BIN_NAME}"
TMP=$(mktemp -t taglibro-install.XXXXXX)
trap 'rm -f "${TMP}"' EXIT

echo "→ Downloading binary (~10 MB) to ${TARGET}…"
curl -fsSL "${ASSET_URL}" -o "${TMP}" || {
  echo "✗ Download failed." >&2
  exit 2
}
mv "${TMP}" "${TARGET}"
chmod +x "${TARGET}"

# ── PATH check ─────────────────────────────────────────────────────
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ON_PATH=1 ;;
  *) ON_PATH=0 ;;
esac

if [ "${ON_PATH}" = "0" ]; then
  RC_LINE='export PATH="$HOME/.local/bin:$PATH"'
  case "${SHELL:-}" in
    */zsh)  RC_FILE="${HOME}/.zshrc" ;;
    */bash) RC_FILE="${HOME}/.bashrc" ;;
    *)      RC_FILE="${HOME}/.profile" ;;
  esac
  echo
  echo "! ${INSTALL_DIR} is not on \$PATH."
  echo "  Add this line to ${RC_FILE}:"
  echo
  echo "    ${RC_LINE}"
  echo
  if [ "${YES}" = "1" ]; then
    echo "${RC_LINE}" >> "${RC_FILE}"
    echo "  ✓ Appended automatically (--yes)."
    echo "  Run \`source ${RC_FILE}\` or open a new shell to pick it up."
  else
    echo "  (Re-run with --yes to append automatically.)"
  fi
fi

# ── verify ─────────────────────────────────────────────────────────
VERSION_OUT=$("${TARGET}" --version 2>&1) || {
  echo "✗ '${TARGET} --version' failed. Output:" >&2
  echo "  ${VERSION_OUT}" >&2
  exit 3
}

echo
echo "✓ Installed ${VERSION_OUT}"
echo "  Binary: ${TARGET}"
echo
echo "Next steps:"
echo "  1. ${BIN_NAME} login         # one-time auth, saves to ~/.config/taglibro"
echo "  2. ${BIN_NAME} new           # create today's diary in \$EDITOR"
echo "  3. ${BIN_NAME} --help        # full command list"
