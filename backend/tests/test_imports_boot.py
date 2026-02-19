from __future__ import annotations

import importlib
import unittest


class ImportsBootTestCase(unittest.TestCase):
    def test_import_create_app(self):
        module = importlib.import_module("app")
        create_app = getattr(module, "create_app", None)
        self.assertTrue(callable(create_app))

    def test_import_main_app(self):
        module = importlib.import_module("main")
        app = getattr(module, "app", None)
        self.assertIsNotNone(app)

    def test_import_auth_routes_segment(self):
        module = importlib.import_module("app.segments.segment_09_users_auth_routes")
        self.assertIsNotNone(module)


if __name__ == "__main__":
    unittest.main()
