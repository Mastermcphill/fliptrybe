from __future__ import annotations

import unittest

from app import create_app
from app.utils.commission import RATES, compute_commission


class ShortletCommissionFivePercentTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        cls.client = cls.app.test_client()

    def test_shortlet_rate_constant_is_five_percent(self):
        self.assertAlmostEqual(float(RATES.get("shortlet_booking", 0.0)), 0.05, places=4)
        self.assertAlmostEqual(compute_commission(1000.0, float(RATES["shortlet_booking"])), 50.0, places=2)

    def test_listing_price_preview_shortlet_uses_five_percent(self):
        res = self.client.post(
            "/api/listings/price-preview",
            json={"base_price": 1000, "listing_type": "shortlet", "seller_role": "merchant"},
        )
        self.assertEqual(res.status_code, 200)
        body = res.get_json(force=True)
        self.assertTrue(body.get("ok"))
        self.assertAlmostEqual(float(body.get("platform_fee") or 0.0), 50.0, places=2)
        self.assertEqual(body.get("rule_applied"), "shortlet_addon_5pct")


if __name__ == "__main__":
    unittest.main()
