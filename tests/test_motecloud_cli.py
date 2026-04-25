from __future__ import annotations

import importlib.util
import pathlib
import unittest

from motecloud_cli import _core as package_cli


SCRIPT_PATH = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "motecloud.py"
SPEC = importlib.util.spec_from_file_location("motecloud_cli", SCRIPT_PATH)
assert SPEC is not None
assert SPEC.loader is not None
standalone_cli = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(standalone_cli)


class CliAssertions:
    cli_module = None

    def test_is_jwt_like(self) -> None:
        self.assertTrue(self.cli_module._is_jwt_like("a.b.c" + "x" * 20))
        self.assertFalse(self.cli_module._is_jwt_like("not-a-jwt"))

    def test_normalize_base_url_https(self) -> None:
        out = self.cli_module._normalize_base_url("https://motecloud.io/api", allow_http=False)
        self.assertEqual(out, "https://motecloud.io")

    def test_normalize_base_url_rejects_http_without_flag(self) -> None:
        with self.assertRaises(SystemExit):
            self.cli_module._normalize_base_url("http://localhost:8000", allow_http=False)

    def test_headers_auto_mode_uses_bearer_for_jwt_like_tokens(self) -> None:
        headers = self.cli_module._headers(
            {"MOTECLOUD_TENANT_TOKEN": "aaaaaaaaaa.bbbbbbbbbb.cccccccccc"},
            "tenant-1",
            "",
            "auto",
        )
        self.assertIn("Authorization", headers)
        self.assertNotIn("X-Tenant-Token", headers)

    def test_headers_auto_mode_uses_static_for_api_key_like_tokens(self) -> None:
        headers = self.cli_module._headers({"MOTECLOUD_API_KEY": "sk_test_abc123"}, "tenant-1", "", "auto")
        self.assertIn("X-Tenant-Token", headers)
        self.assertNotIn("Authorization", headers)

    def test_base_and_tenant_validates_timeout_and_retries(self) -> None:
        parser = self.cli_module._build_parser()
        args = parser.parse_args(["prepare", "--task", "test", "--timeout", "0", "--tenant-id", "t", "--token", "x.y.z"])
        with self.assertRaises(SystemExit):
            self.cli_module._base_and_tenant(args, {})


class TestStandaloneMotecloudCli(CliAssertions, unittest.TestCase):
    cli_module = standalone_cli


class TestPackageMotecloudCli(CliAssertions, unittest.TestCase):
    cli_module = package_cli


if __name__ == "__main__":
    unittest.main()
