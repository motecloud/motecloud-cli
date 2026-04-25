#!/usr/bin/env sh
# install-cli.sh — One-line installer for motecloud-cli
#
# Usage:
#   curl -sSL https://motecloud.io/install-cli.sh | sh
#   curl -sSL https://motecloud.io/install-cli.sh | sh -s -- --prefix /usr/local
#   curl -sSL https://motecloud.io/install-cli.sh | sh -s -- --version v0.2.0
#
# Options:
#   --version VERSION   Install a specific version (default: latest)
#   --prefix  DIR       Install prefix (default: /usr/local)
#   --no-verify         Skip SHA256 checksum verification
#   --allow-http        Allow non-HTTPS download (for testing only)
#
# Environment:
#   MOTECLOUD_CLI_VERSION   Override version (same as --version)
#   MOTECLOUD_CLI_PREFIX    Override prefix (same as --prefix)

set -eu

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
INSTALL_VERSION="${MOTECLOUD_CLI_VERSION:-latest}"
INSTALL_PREFIX="${MOTECLOUD_CLI_PREFIX:-/usr/local}"
VERIFY=1
ALLOW_HTTP=0
GITHUB_REPO="motecloud/motecloud-cli"
GITHUB_RELEASES="https://github.com/${GITHUB_REPO}/releases"
FALLBACK_BASE="https://motecloud.io/cli"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --version)  INSTALL_VERSION="$2"; shift 2 ;;
    --prefix)   INSTALL_PREFIX="$2"; shift 2 ;;
    --no-verify) VERIFY=0; shift ;;
    --allow-http) ALLOW_HTTP=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf '\033[1;34m[motecloud-cli]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[motecloud-cli]\033[0m %s\n' "$*"; }
err()   { printf '\033[1;31m[motecloud-cli]\033[0m ERROR: %s\n' "$*" >&2; exit 1; }
warn()  { printf '\033[1;33m[motecloud-cli]\033[0m WARN: %s\n' "$*" >&2; }

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "required command not found: $1"
  fi
}

# ---------------------------------------------------------------------------
# Validate environment
# ---------------------------------------------------------------------------
need_cmd python3
need_cmd curl

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
PYTHON_MAJOR=$(python3 -c 'import sys; print(sys.version_info[0])')
PYTHON_MINOR=$(python3 -c 'import sys; print(sys.version_info[1])')

if [ "$PYTHON_MAJOR" -lt 3 ] || { [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 10 ]; }; then
  err "Python 3.10+ required, found $PYTHON_VERSION"
fi

info "Python $PYTHON_VERSION detected"

# ---------------------------------------------------------------------------
# Resolve latest version if needed
# ---------------------------------------------------------------------------
if [ "$INSTALL_VERSION" = "latest" ]; then
  info "Resolving latest version..."
  INSTALL_VERSION=$(curl -sSL --fail \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null) \
    || INSTALL_VERSION="v0.2.0"
  info "Latest version: $INSTALL_VERSION"
fi

VERSION_BARE="${INSTALL_VERSION#v}"

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
TARBALL="motecloud-cli-v${VERSION_BARE}.tar.gz"
DOWNLOAD_URL="${GITHUB_RELEASES}/download/v${VERSION_BARE}/${TARBALL}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

info "Downloading $TARBALL..."
if ! curl -sSL --fail "$DOWNLOAD_URL" -o "$TMP_DIR/$TARBALL"; then
  warn "GitHub download failed, trying fallback URL..."
  DOWNLOAD_URL="${FALLBACK_BASE}/${TARBALL}"
  curl -sSL --fail "$DOWNLOAD_URL" -o "$TMP_DIR/$TARBALL" \
    || err "Failed to download $TARBALL from all sources"
fi

# ---------------------------------------------------------------------------
# Verify checksum
# ---------------------------------------------------------------------------
if [ "$VERIFY" = "1" ]; then
  HASH_URL="${GITHUB_RELEASES}/download/v${VERSION_BARE}/${TARBALL}.sha256"
  info "Verifying checksum..."
  if curl -sSL --fail "$HASH_URL" -o "$TMP_DIR/${TARBALL}.sha256" 2>/dev/null; then
    EXPECTED=$(cat "$TMP_DIR/${TARBALL}.sha256" | awk '{print $1}')
    ACTUAL=$(python3 -c "
import hashlib, sys
data = open('$TMP_DIR/$TARBALL','rb').read()
print(hashlib.sha256(data).hexdigest())
")
    if [ "$EXPECTED" != "$ACTUAL" ]; then
      err "Checksum mismatch! expected=$EXPECTED actual=$ACTUAL"
    fi
    ok "Checksum verified"
  else
    warn "Could not fetch checksum file; skipping verification"
  fi
fi

# ---------------------------------------------------------------------------
# Extract and install
# ---------------------------------------------------------------------------
info "Extracting..."
tar -xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"

# The tarball normally extracts to motecloud-cli-v<version>/.
EXTRACT_DIR="$TMP_DIR/motecloud-cli-v${VERSION_BARE}"
if [ ! -d "$EXTRACT_DIR" ]; then
  # Some tar implementations drop the v prefix
  EXTRACT_DIR="$TMP_DIR/motecloud-cli-${VERSION_BARE}"
fi
if [ ! -d "$EXTRACT_DIR" ]; then
  EXTRACT_DIR="$TMP_DIR/v${VERSION_BARE}"
fi
if [ ! -f "$EXTRACT_DIR/motecloud.py" ]; then
  MOTE_SCRIPT=$(find "$TMP_DIR" -mindepth 2 -maxdepth 3 -type f -name motecloud.py | head -1)
  [ -n "$MOTE_SCRIPT" ] && EXTRACT_DIR=$(dirname "$MOTE_SCRIPT")
fi
[ -f "$EXTRACT_DIR/motecloud.py" ] || err "Could not find extracted motecloud.py"

BIN_DIR="${INSTALL_PREFIX}/bin"
LIB_DIR="${INSTALL_PREFIX}/lib/motecloud-cli"

info "Installing to ${INSTALL_PREFIX}..."

# Create directories (may need sudo — inform user)
if ! mkdir -p "$BIN_DIR" "$LIB_DIR" 2>/dev/null; then
  warn "Cannot write to $INSTALL_PREFIX — you may need to run as root or set --prefix to a user-writable path"
  warn "Tip: --prefix $HOME/.local"
  err "Installation failed: permission denied"
fi

# Install the Python module
cp "$EXTRACT_DIR/motecloud.py" "$LIB_DIR/motecloud.py"
chmod 644 "$LIB_DIR/motecloud.py"

# Write a launcher wrapper to bin/
cat > "$BIN_DIR/motecloud" <<LAUNCHER
#!/usr/bin/env sh
exec python3 "$LIB_DIR/motecloud.py" "\$@"
LAUNCHER
chmod 755 "$BIN_DIR/motecloud"

# ---------------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------------
INSTALLED_VERSION=$("$BIN_DIR/motecloud" --version 2>&1 || true)
ok "Installed: $INSTALLED_VERSION"
ok "Binary at: $BIN_DIR/motecloud"

cat <<MSG

  Next steps:
    1. Export your credentials:
         export MOTECLOUD_TENANT_ID=your-tenant-id
         export MOTECLOUD_TENANT_TOKEN=your-token

    2. Verify:
         motecloud --version

    3. Prime context:
         motecloud prepare --task "My first task" --agent "my-agent"

  Full docs: https://motecloud.io/docs/reference/cli-install

MSG
