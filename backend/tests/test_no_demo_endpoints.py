from __future__ import annotations

import unittest

from app import create_app


class NoDemoEndpointsTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        cls.client = cls.app.test_client()

    def test_route_map_has_no_demo_endpoints(self):
        rules = [rule.rule for rule in self.app.url_map.iter_rules() if rule.rule.startswith("/api/")]
        self.assertFalse(any("/demo" in rule for rule in rules), msg="\n".join(sorted(rules)))

    def test_known_removed_demo_routes_return_not_found(self):
        endpoints = [
            ("post", "/api/demo/seed"),
            ("get", "/api/demo/ledger_summary"),
            ("post", "/api/admin/demo/seed-listing"),
            ("post", "/api/admin/demo/seed-nationwide"),
            ("post", "/api/admin/demo/seed-leaderboards"),
            ("post", "/api/admin/notify-queue/demo/enqueue"),
            ("post", "/api/wallet/topup-demo"),
            ("post", "/api/notify/flush-demo"),
            ("post", "/api/receipts/demo"),
            ("post", "/api/merchants/1/simulate-sale"),
        ]
        for method, path in endpoints:
            with self.subTest(path=path, method=method):
                res = getattr(self.client, method)(path)
                self.assertEqual(res.status_code, 404)


if __name__ == "__main__":
    unittest.main()

