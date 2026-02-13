from __future__ import annotations

import unittest

from app.utils.commission import compute_order_commissions_minor


class CommissionMinorTestCase(unittest.TestCase):
    def test_declutter_and_shortlet_sale_fee_are_five_percent(self):
        declutter = compute_order_commissions_minor(
            sale_kind="declutter",
            sale_charge_minor=100000,
            delivery_minor=0,
            inspection_minor=0,
            is_top_tier=False,
        )
        shortlet = compute_order_commissions_minor(
            sale_kind="shortlet",
            sale_charge_minor=100000,
            delivery_minor=0,
            inspection_minor=0,
            is_top_tier=False,
        )
        self.assertEqual(int(declutter["sale"]["fee_minor"]), 5000)
        self.assertEqual(int(shortlet["sale"]["fee_minor"]), 5000)

    def test_half_up_rounding_and_splits(self):
        snapshot = compute_order_commissions_minor(
            sale_kind="declutter",
            sale_charge_minor=10,  # 5% = 0.5 -> 1 (half-up)
            delivery_minor=12345,  # 10% = 1234.5 -> 1235
            inspection_minor=99,  # 10% = 9.9 -> 10
            is_top_tier=False,
        )
        self.assertEqual(int(snapshot["sale"]["fee_minor"]), 1)
        self.assertEqual(int(snapshot["delivery"]["platform_minor"]), 1235)
        self.assertEqual(int(snapshot["delivery"]["actor_minor"]), 11110)
        self.assertEqual(int(snapshot["inspection"]["platform_minor"]), 10)
        self.assertEqual(int(snapshot["inspection"]["actor_minor"]), 89)

    def test_top_tier_incentive_split(self):
        snapshot = compute_order_commissions_minor(
            sale_kind="declutter",
            sale_charge_minor=100000,
            delivery_minor=0,
            inspection_minor=0,
            is_top_tier=True,
        )
        self.assertEqual(int(snapshot["sale"]["fee_minor"]), 5000)
        self.assertEqual(int(snapshot["sale"]["top_tier_incentive_minor"]), 4231)
        self.assertEqual(int(snapshot["sale"]["platform_minor"]), 769)


if __name__ == "__main__":
    unittest.main()
