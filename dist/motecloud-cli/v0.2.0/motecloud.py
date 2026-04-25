#!/usr/bin/env python3
"""Zero-dependency Motecloud CLI for agent workflows.

This script wraps the common memory/session HTTP routes so non-MCP agents can use
simple commands instead of remembering endpoint and payload details.

License (MIT)

Copyright (c) 2026 Motecloud contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}
DEFAULT_BASE_URL = "https://motecloud.io"
DEFAULT_TIMEOUT_SECONDS = 30.0
CLI_VERSION = "0.2.0"


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, hdrs, newurl):
        return None


def _load_dotenv(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists() or not path.is_file():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            out[key] = value
    return out


def _resolve_env() -> dict[str, str]:
    repo_root = Path(__file__).resolve().parents[1]
    values = _load_dotenv(Path.cwd() / ".env")
    values.update(_load_dotenv(repo_root / ".env"))
    values.update({k: v for k, v in os.environ.items() if isinstance(v, str)})
    return values


def _required_str(value: str, flag_name: str) -> str:
    text = str(value or "").strip()
    if text:
        return text
    raise SystemExit(f"missing required value for {flag_name}")


def _is_jwt_like(value: str) -> bool:
    return value.count(".") == 2 and len(value) >= 20


def _headers(env_values: dict[str, str], tenant_id: str, command_token: str = "", auth_mode: str = "auto") -> dict[str, str]:
    token = str(
        command_token
        or env_values.get("MOTECLOUD_TENANT_TOKEN", "")
        or env_values.get("MOTECLOUD_API_KEY", "")
    ).strip()
    if not token:
        raise SystemExit("missing auth token: set MOTECLOUD_TENANT_TOKEN/MOTECLOUD_API_KEY or use --token")

    mode = (auth_mode or env_values.get("MOTECLOUD_AUTH_MODE", "auto")).strip().lower()
    if mode not in {"auto", "bearer", "static"}:
        raise SystemExit("invalid auth mode: expected auto|bearer|static")
    if mode == "auto":
        mode = "bearer" if _is_jwt_like(token) else "static"

    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Tenant-Id": tenant_id,
        "User-Agent": f"motecloud-cli/{CLI_VERSION}",
    }
    if mode == "bearer":
        headers["Authorization"] = f"Bearer {token}"
    else:
        headers["X-Tenant-Token"] = token
    return headers


def _normalize_base_url(base_url: str, allow_http: bool) -> str:
    value = str(base_url or "").strip()
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise SystemExit("invalid --base-url: expected absolute URL like https://motecloud.io")
    if parsed.scheme != "https" and not allow_http:
        raise SystemExit("refusing non-HTTPS base URL unless --allow-http is set")
    return f"{parsed.scheme}://{parsed.netloc}".rstrip("/")


def _post_json(
    *,
    base_url: str,
    path: str,
    payload: dict[str, Any],
    headers: dict[str, str],
    timeout_seconds: float,
    max_retries: int,
) -> dict[str, Any]:
    url = f"{base_url.rstrip('/')}{path}"
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    opener = urllib.request.build_opener(_NoRedirect())

    for attempt in range(max_retries + 1):
        try:
            with opener.open(req, timeout=timeout_seconds) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
                if not raw.strip():
                    return {"ok": True, "status": resp.status, "result": {}}
                return json.loads(raw)
        except urllib.error.HTTPError as exc:
            if exc.code in {301, 302, 303, 307, 308}:
                location = exc.headers.get("Location", "") if exc.headers else ""
                raise SystemExit(f"redirect blocked for security: {path} -> {location}")
            raw = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
            parsed: dict[str, Any]
            try:
                parsed = json.loads(raw) if raw else {}
            except json.JSONDecodeError:
                parsed = {"detail": raw[:400]}
            if exc.code in RETRYABLE_STATUS_CODES and attempt < max_retries:
                sleep_s = min(2.0, 0.25 * (2**attempt) + random.uniform(0.0, 0.1))
                time.sleep(sleep_s)
                continue
            raise SystemExit(f"HTTP {exc.code} {path}: {json.dumps(parsed, ensure_ascii=True)}")
        except urllib.error.URLError as exc:
            if attempt < max_retries:
                sleep_s = min(2.0, 0.25 * (2**attempt) + random.uniform(0.0, 0.1))
                time.sleep(sleep_s)
                continue
            raise SystemExit(f"request failed for {path}: {exc}")

    raise SystemExit(f"request failed after retries: {path}")


def _common_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--base-url", default="", help="API base URL (default: MOTECLOUD_BASE_URL or https://motecloud.io)")
    parser.add_argument("--tenant-id", default="", help="Tenant ID (default: MOTECLOUD_TENANT_ID)")
    parser.add_argument("--token", default="", help="Auth token or API key (default: MOTECLOUD_TENANT_TOKEN or MOTECLOUD_API_KEY)")
    parser.add_argument("--auth-mode", choices=["auto", "bearer", "static"], default="auto", help="Auth header mode (default: auto)")
    parser.add_argument("--allow-http", action="store_true", help="Allow non-HTTPS base URLs (for local development only)")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS, help="Request timeout in seconds")
    parser.add_argument("--retries", type=int, default=2, help="Retry attempts for transient failures")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Zero-dependency CLI wrapper for Motecloud memory/session APIs.")
    parser.add_argument("--version", action="version", version=f"motecloud-cli {CLI_VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    prepare = sub.add_parser("prepare", help="Prime context for a task")
    _common_options(prepare)
    prepare.add_argument("--task", required=True, help="Task description")
    prepare.add_argument("--agent", default="", help="Agent ID")
    prepare.add_argument("--session-id", default="", help="Optional session ID")
    prepare.add_argument("--token-budget", type=int, default=2000)

    capture = sub.add_parser("capture", help="Capture a quick task by opening and appending to a session")
    _common_options(capture)
    capture.add_argument("--title", required=True, help="Task title")
    capture.add_argument("--desc", required=True, help="Task description")
    capture.add_argument("--id", default="", help="Session ID (default: autogenerated)")
    capture.add_argument("--agent", default="", help="Agent ID")
    capture.add_argument("--importance", type=float, default=0.8)

    session = sub.add_parser("session", help="Session operations")
    session_sub = session.add_subparsers(dest="session_command", required=True)

    open_p = session_sub.add_parser("open", help="Open or resume a session")
    _common_options(open_p)
    open_p.add_argument("--id", required=True, help="Session ID")
    open_p.add_argument("--agent", default="", help="Agent ID")
    open_p.add_argument("--token-budget", type=int, default=0)

    append_p = session_sub.add_parser("append", help="Append one observation to a session")
    _common_options(append_p)
    append_p.add_argument("--id", required=True, help="Session ID")
    append_p.add_argument("--content", required=True, help="Observation text")
    append_p.add_argument("--source", default="cli:session_append", help="Source identifier")
    append_p.add_argument("--importance", type=float, default=0.7)

    flush_p = session_sub.add_parser("flush", help="Consolidate a session without closing")
    _common_options(flush_p)
    flush_p.add_argument("--id", required=True, help="Session ID")
    flush_p.add_argument("--smart", action="store_true", help="Enable smart consolidation")

    close_p = session_sub.add_parser("close", help="Close a session")
    _common_options(close_p)
    close_p.add_argument("--id", required=True, help="Session ID")
    close_p.add_argument("--summary", default="", help="Optional summary")
    close_p.add_argument("--smart", action="store_true", help="Enable smart consolidation")

    finalize_p = session_sub.add_parser("finalize", help="Append observation(s) and close session")
    _common_options(finalize_p)
    finalize_p.add_argument("--id", required=True, help="Session ID")
    finalize_p.add_argument("--content", required=True, help="Final observation to append")
    finalize_p.add_argument("--summary", default="", help="Optional summary")
    finalize_p.add_argument("--agent", default="", help="Agent ID")

    status_p = session_sub.add_parser("status", help="Get session status")
    _common_options(status_p)
    status_p.add_argument("--id", required=True, help="Session ID")

    return parser


def _base_and_tenant(args: argparse.Namespace, env_values: dict[str, str]) -> tuple[str, str, dict[str, str]]:
    base_url = _normalize_base_url(
        str(args.base_url or env_values.get("MOTECLOUD_BASE_URL", DEFAULT_BASE_URL)).strip() or DEFAULT_BASE_URL,
        allow_http=bool(getattr(args, "allow_http", False)),
    )
    tenant_id = _required_str(str(args.tenant_id or env_values.get("MOTECLOUD_TENANT_ID", "")), "--tenant-id/MOTECLOUD_TENANT_ID")
    timeout_s = float(getattr(args, "timeout", DEFAULT_TIMEOUT_SECONDS))
    retries = int(getattr(args, "retries", 2))
    if timeout_s <= 0 or timeout_s > 300:
        raise SystemExit("invalid --timeout: expected value in (0, 300]")
    if retries < 0 or retries > 8:
        raise SystemExit("invalid --retries: expected integer in [0, 8]")
    headers = _headers(
        env_values,
        tenant_id,
        str(getattr(args, "token", "")),
        str(getattr(args, "auth_mode", "auto")),
    )
    return base_url, tenant_id, headers


def _cmd_prepare(args: argparse.Namespace, env_values: dict[str, str]) -> dict[str, Any]:
    base_url, tenant_id, headers = _base_and_tenant(args, env_values)
    payload = {
        "tenant_id": tenant_id,
        "task_description": args.task,
        "token_budget": int(args.token_budget),
        "agent_id": str(args.agent or "").strip(),
        "session_id": str(args.session_id or "").strip(),
    }
    return _post_json(
        base_url=base_url,
        path="/v2/prime-context",
        payload=payload,
        headers=headers,
        timeout_seconds=float(args.timeout),
        max_retries=max(0, int(args.retries)),
    )


def _cmd_capture(args: argparse.Namespace, env_values: dict[str, str]) -> dict[str, Any]:
    base_url, tenant_id, headers = _base_and_tenant(args, env_values)
    session_id = str(args.id or "").strip() or f"cli-task-{uuid.uuid4().hex[:12]}"

    opened = _post_json(
        base_url=base_url,
        path="/v2/session/open",
        payload={
            "tenant_id": tenant_id,
            "session_id": session_id,
            "agent_id": str(args.agent or "").strip(),
            "token_budget": 0,
            "metadata": {},
        },
        headers=headers,
        timeout_seconds=float(args.timeout),
        max_retries=max(0, int(args.retries)),
    )

    content = f"{args.title}\n\n{args.desc}".strip()
    appended = _post_json(
        base_url=base_url,
        path="/v2/session/append",
        payload={
            "tenant_id": tenant_id,
            "session_id": session_id,
            "content": content,
            "source_id": "cli:task_capture",
            "importance_score": float(args.importance),
            "tags": {},
            "idempotency_key": f"cli-task-capture:{session_id}",
            "working_memory_budget_tokens": 0,
        },
        headers=headers,
        timeout_seconds=float(args.timeout),
        max_retries=max(0, int(args.retries)),
    )

    return {"tenant_id": tenant_id, "session_id": session_id, "opened": opened, "appended": appended}


def _cmd_session(args: argparse.Namespace, env_values: dict[str, str]) -> dict[str, Any]:
    base_url, tenant_id, headers = _base_and_tenant(args, env_values)
    cmd = str(args.session_command)

    if cmd == "open":
        payload = {
            "tenant_id": tenant_id,
            "session_id": args.id,
            "agent_id": str(args.agent or "").strip(),
            "token_budget": int(args.token_budget),
            "metadata": {},
        }
        path = "/v2/session/open"
    elif cmd == "append":
        payload = {
            "tenant_id": tenant_id,
            "session_id": args.id,
            "content": args.content,
            "source_id": str(args.source or "cli:session_append").strip(),
            "importance_score": float(args.importance),
            "tags": {},
            "idempotency_key": f"cli-session-append:{args.id}:{uuid.uuid4().hex[:8]}",
            "working_memory_budget_tokens": 0,
        }
        path = "/v2/session/append"
    elif cmd == "flush":
        payload = {
            "tenant_id": tenant_id,
            "session_id": args.id,
            "smart_consolidation": bool(args.smart),
        }
        path = "/v2/session/flush"
    elif cmd == "close":
        payload = {
            "tenant_id": tenant_id,
            "session_id": args.id,
            "summary": str(args.summary or "").strip(),
            "smart_consolidation": bool(args.smart),
            "min_sequence": 0,
        }
        path = "/v2/session/close"
    elif cmd == "finalize":
        payload = {
            "tenant_id": tenant_id,
            "session_id": args.id,
            "agent_id": str(args.agent or "").strip(),
            "token_budget": 0,
            "metadata": {},
            "summary": str(args.summary or "").strip(),
            "smart_consolidation": False,
            "working_memory_budget_tokens": 0,
            "observations": [
                {
                    "content": args.content,
                    "source_id": "cli:session_finalize",
                    "importance_score": 0.7,
                    "tags": {},
                    "idempotency_key": f"cli-session-finalize:{args.id}:{uuid.uuid4().hex[:8]}",
                }
            ],
        }
        path = "/v2/session/finalize"
    elif cmd == "status":
        payload = {
            "tenant_id": tenant_id,
        }
        path = f"/v2/session/{args.id}/status"
    else:
        raise SystemExit(f"unknown session command: {cmd}")

    return _post_json(
        base_url=base_url,
        path=path,
        payload=payload,
        headers=headers,
        timeout_seconds=float(args.timeout),
        max_retries=max(0, int(args.retries)),
    )


def main(argv: list[str]) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    env_values = _resolve_env()

    if args.command == "prepare":
        result = _cmd_prepare(args, env_values)
    elif args.command == "capture":
        result = _cmd_capture(args, env_values)
    elif args.command == "session":
        result = _cmd_session(args, env_values)
    else:
        raise SystemExit(f"unknown command: {args.command}")

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
