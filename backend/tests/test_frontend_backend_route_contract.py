from __future__ import annotations

import re
import unittest
from pathlib import Path

from app import create_app


class FrontendBackendRouteContractTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.frontend_lib = (
            Path(__file__).resolve().parents[2] / "frontend" / "lib"
        )

    def _frontend_paths(self) -> set[str]:
        pattern = re.compile(r"ApiConfig\.api\(\s*['\"]([^'\"]+)['\"]")
        paths: set[str] = set()
        for path in self.frontend_lib.rglob("*.dart"):
            text = path.read_text(encoding="utf-8", errors="ignore")
            for match in pattern.finditer(text):
                paths.add(match.group(1))
        return paths

    @staticmethod
    def _normalize_frontend_path(raw: str) -> str:
        path = raw.split("?", 1)[0]
        raw_path = path
        path = re.sub(r"\$\{[^}]+\}", "{}", path)
        path = re.sub(r"\$[A-Za-z_][A-Za-z0-9_]*", "{}", path)
        if not path.startswith("/api"):
            path = f"/api{path}"
        # Handles optional query suffix variables appended directly to route
        # literals e.g. '/orders/my$suffix' -> '/orders/my'.
        if re.search(r"[A-Za-z0-9]\$(\{)?[A-Za-z_][A-Za-z0-9_]*(\})?$", raw_path):
            if path.endswith("{}"):
                path = path[:-2]
        return path.rstrip("/") or "/"

    @staticmethod
    def _normalize_backend_rule(raw: str) -> str:
        path = re.sub(r"<[^>]+>", "{}", raw)
        return path.rstrip("/") or "/"

    @staticmethod
    def _as_regex(normalized_rule: str) -> re.Pattern[str]:
        escaped = re.escape(normalized_rule).replace(r"\{\}", r"[^/]+")
        return re.compile(rf"^{escaped}$")

    def test_frontend_api_paths_have_backend_routes(self):
        backend_rules = {
            self._normalize_backend_rule(str(rule.rule))
            for rule in self.app.url_map.iter_rules()
        }
        backend_matchers = [self._as_regex(rule) for rule in sorted(backend_rules)]

        allow_unmatched: set[str] = set()
        unmatched: list[str] = []
        for raw in sorted(self._frontend_paths()):
            normalized = self._normalize_frontend_path(raw)
            if normalized in allow_unmatched:
                continue
            if any(regex.match(normalized) for regex in backend_matchers):
                continue
            unmatched.append(f"{raw} -> {normalized}")

        self.assertEqual(
            unmatched,
            [],
            msg="Frontend API routes missing in backend:\n" + "\n".join(unmatched),
        )


if __name__ == "__main__":
    unittest.main()
