from __future__ import annotations

import re
import unittest
from pathlib import Path


class FrontendDeadCallbackScanTestCase(unittest.TestCase):
    def test_no_direct_noop_tap_handlers(self):
        frontend_lib = Path(__file__).resolve().parents[2] / "frontend" / "lib"
        patterns = (
            re.compile(r"onPressed\s*:\s*\(\)\s*\{\s*\}"),
            re.compile(r"onTap\s*:\s*\(\)\s*\{\s*\}"),
        )
        hits: list[str] = []

        for path in frontend_lib.rglob("*.dart"):
            text = path.read_text(encoding="utf-8", errors="ignore")
            lines = text.splitlines()
            for lineno, line in enumerate(lines, start=1):
                for pattern in patterns:
                    if pattern.search(line):
                        hits.append(f"{path}:{lineno}:{line.strip()}")

        self.assertEqual(
            hits,
            [],
            msg="Found direct no-op callbacks in frontend:\n" + "\n".join(hits),
        )


if __name__ == "__main__":
    unittest.main()
