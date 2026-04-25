# Installing motecloud-cli

`motecloud-cli` is a zero-dependency Python CLI for using Motecloud memory and session APIs from any agent or shell environment that lacks MCP access.

**Current version:** `v0.2.0` · [Release notes](https://github.com/motecloud/motecloud-cli/releases/tag/v0.2.0)

---

## Quick install (recommended)

```sh
curl -sSL https://raw.githubusercontent.com/motecloud/motecloud-cli/main/scripts/install-cli.sh | sh
```

This downloads the latest release, verifies the SHA256 checksum, and installs `motecloud` to `/usr/local/bin`. Requires Python 3.10+.

To install to a custom prefix (e.g., no sudo):

```sh
curl -sSL https://raw.githubusercontent.com/motecloud/motecloud-cli/main/scripts/install-cli.sh | sh -s -- --prefix ~/.local
```

To pin a specific version:

```sh
curl -sSL https://raw.githubusercontent.com/motecloud/motecloud-cli/main/scripts/install-cli.sh | sh -s -- --version v0.2.0
```

---

## pip / pipx

```sh
pip install motecloud-cli
# or, isolated:
pipx install motecloud-cli
```

The `motecloud` command will be available after installation. Works on Python 3.10+, no third-party dependencies.

---

## Manual download

Download the standalone single-file script — no installation needed:

| File | SHA256 |
|------|--------|
| [motecloud.py](https://github.com/motecloud/motecloud-cli/releases/download/v0.2.0/motecloud.py) | `33892a5b26835310f5c13cb6b422fc83dd1500daad63f213bc0682129fca67d4` |
| [motecloud.sh](https://github.com/motecloud/motecloud-cli/releases/download/v0.2.0/motecloud.sh) | `4dd2d4a7d7025c44df31172857344ebad117711c471ec4f6a2fe22484ac4aa05` |
| [motecloud-cli-v0.2.0.tar.gz](https://github.com/motecloud/motecloud-cli/releases/download/v0.2.0/motecloud-cli-v0.2.0.tar.gz) | `5b18373c4b49769c099381088d337f9349f80b722026b087da54ba8dd51054bc` |

Verify before running:

```sh
curl -sSLO https://github.com/motecloud/motecloud-cli/releases/download/v0.2.0/motecloud.py
curl -sSLO https://github.com/motecloud/motecloud-cli/releases/download/v0.2.0/motecloud.py.sha256
python3 -c "
import hashlib
data = open('motecloud.py','rb').read()
expected = open('motecloud.py.sha256').read().strip().split()[0]
assert hashlib.sha256(data).hexdigest() == expected, 'checksum mismatch!'
print('OK')
"
python3 motecloud.py --help
```

---

## Homebrew

```sh
brew tap motecloud/motecloud
brew install motecloud-cli
```

Or directly from the formula URL:

```sh
brew install https://raw.githubusercontent.com/motecloud/motecloud-cli/main/packaging/homebrew/motecloud.rb
```

---

## Configuration

Set these environment variables (or write them to a `.env` file in the working directory):

| Variable | Required | Description |
|----------|----------|-------------|
| `MOTECLOUD_TENANT_ID` | Yes | Your tenant identifier |
| `MOTECLOUD_TENANT_TOKEN` | Yes* | Static tenant token |
| `MOTECLOUD_API_KEY` | Yes* | API key (alias for token) |
| `MOTECLOUD_BASE_URL` | No | API base URL (default: `https://motecloud.io`) |
| `MOTECLOUD_AUTH_MODE` | No | `auto` (default), `bearer`, or `static` |

*One of `MOTECLOUD_TENANT_TOKEN` or `MOTECLOUD_API_KEY` is required.

---

## Usage

```sh
# Prime context before starting work
motecloud prepare --task "Investigate auth regression" --agent "my-agent"

# Open a working-memory session
motecloud session open --id "my-agent:pr-123" --agent "my-agent"

# Append an observation
motecloud session append --id "my-agent:pr-123" --content "Found root cause in token.py line 42"

# Flush mid-session
motecloud session flush --id "my-agent:pr-123"

# Close with summary
motecloud session close --id "my-agent:pr-123" --summary "Fixed token expiry logic, tests pass"

# Capture a quick one-off task (opens + appends atomically)
motecloud capture --title "Quick fix" --desc "Patched null check in auth middleware"
```

All commands output JSON. See `motecloud --help` or `motecloud <command> --help` for full options.

---

## Security notes

- HTTPS is required by default. Use `--allow-http` only for trusted local development endpoints.
- HTTP redirects are blocked at the request level to prevent token leakage.
- The `motecloud.py` standalone script has no external dependencies — review it directly before running.
- Checksums are published alongside every release at the [GitHub Releases page](https://github.com/motecloud/motecloud-cli/releases).

---

## For CI / agent environments

In GitHub Actions or similar:

```yaml
- name: Install motecloud-cli
  run: curl -sSL https://raw.githubusercontent.com/motecloud/motecloud-cli/main/scripts/install-cli.sh | sh
  env:
    MOTECLOUD_CLI_PREFIX: ${{ runner.tool_cache }}/motecloud

- name: Prime context
  run: motecloud prepare --task "${{ github.event.head_commit.message }}" --agent "ci"
  env:
    MOTECLOUD_TENANT_ID: ${{ vars.MOTECLOUD_TENANT_ID }}
    MOTECLOUD_TENANT_TOKEN: ${{ secrets.MOTECLOUD_TENANT_TOKEN }}
```

For agents that cannot use MCP (e.g., Jules, Devin, custom runners), copy `motecloud.py` directly into your repo or agent workspace and call it with `python3 motecloud.py <command>`.

---

## Updating

```sh
# Re-run the installer to get the latest version:
curl -sSL https://raw.githubusercontent.com/motecloud/motecloud-cli/main/scripts/install-cli.sh | sh

# Or with pip:
pip install --upgrade motecloud-cli
```

---

## Uninstalling

```sh
# If installed via the curl installer:
rm /usr/local/bin/motecloud /usr/local/lib/motecloud-cli/motecloud.py

# If installed via pip:
pip uninstall motecloud-cli

# If installed via Homebrew:
brew uninstall motecloud-cli
```
