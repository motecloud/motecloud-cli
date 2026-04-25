#!/usr/bin/env python3
"""Synchronize the standalone CLI into the importable package module."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STANDALONE = ROOT / "scripts" / "motecloud.py"
PACKAGE_CORE = ROOT / "motecloud_cli" / "_core.py"

PACKAGE_DOCSTRING = '''"""Core CLI logic for motecloud-cli (pip-installable module copy).

This module is the authoritative source for the pip-installed package.
The standalone single-file version lives at scripts/motecloud.py and is
kept in sync by scripts/sync_cli.py on each release. Both carry the same
CLI_VERSION.
"""
# NOTE: Keep in sync with scripts/motecloud.py.
# Run `make sync-cli` after editing the standalone script.

'''

STANDALONE_ENV = '''def _resolve_env() -> dict[str, str]:
    repo_root = Path(__file__).resolve().parents[1]
    values = _load_dotenv(Path.cwd() / ".env")
    values.update(_load_dotenv(repo_root / ".env"))
    values.update({k: v for k, v in os.environ.items() if isinstance(v, str)})
    return values
'''

PACKAGE_ENV = '''def _resolve_env() -> dict[str, str]:
    values = _load_dotenv(Path.cwd() / ".env")
    values.update({k: v for k, v in os.environ.items() if isinstance(v, str)})
    return values
'''


def _replace_first_docstring(source: str) -> str:
    if source.startswith("#!/usr/bin/env python3\n"):
        source = source.split("\n", 1)[1]
    if not source.startswith('"""'):
        raise SystemExit("standalone CLI must start with a module docstring")
    end = source.find('"""\n', 3)
    if end < 0:
        raise SystemExit("could not find standalone module docstring end")
    return PACKAGE_DOCSTRING + source[end + 4 :].lstrip("\n")


def main() -> int:
    source = STANDALONE.read_text(encoding="utf-8")
    package_source = _replace_first_docstring(source)
    if STANDALONE_ENV not in package_source:
        raise SystemExit("expected standalone _resolve_env block was not found")
    package_source = package_source.replace(STANDALONE_ENV, PACKAGE_ENV, 1)
    package_source = package_source.replace(
        "def main(argv: list[str]) -> int:\n"
        "    parser = _build_parser()\n",
        "def main(argv: list[str] | None = None) -> int:\n"
        "    if argv is None:\n"
        "        argv = sys.argv[1:]\n"
        "    parser = _build_parser()\n",
        1,
    )
    package_source = package_source.replace(
        'if __name__ == "__main__":\n    raise SystemExit(main(sys.argv[1:]))\n',
        'if __name__ == "__main__":\n    raise SystemExit(main())\n',
        1,
    )
    PACKAGE_CORE.write_text(package_source, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
