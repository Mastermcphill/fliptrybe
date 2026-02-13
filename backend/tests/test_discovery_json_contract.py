from datetime import datetime
import json
import unittest

from app import create_app
from app.extensions import db
from app.models import Listing, Shortlet


LISTING_KEYS = {
    "id",
    "title",
    "price",
    "state",
    "city",
    "ranking_score",
    "ranking_reason",
}

SHORTLET_KEYS = {
    "id",
    "title",
    "nightly_price",
    "state",
    "city",
    "ranking_score",
    "ranking_reason",
}


class DiscoveryJsonContractTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
            if not Listing.query.filter(Listing.title == "JSON Contract Listing").first():
                db.session.add(
                    Listing(
                        title="JSON Contract Listing",
                        description="Contract check listing payload.",
                        category="declutter",
                        price=25000.0,
                        date_posted=datetime.utcnow(),
                        state="Lagos",
                        city="Ikeja",
                        locality="Computer Village",
                        image_path="",
                    )
                )
            if not Shortlet.query.filter(Shortlet.title == "JSON Contract Shortlet").first():
                db.session.add(
                    Shortlet(
                        title="JSON Contract Shortlet",
                        description="Contract check shortlet payload.",
                        state="Lagos",
                        city="Ikeja",
                        locality="GRA",
                        nightly_price=45000.0,
                    )
                )
            db.session.commit()
        cls.client = cls.app.test_client()

    def _assert_discovery_shape(self, path: str):
        response = self.client.get(path)
        self.assertEqual(response.status_code, 200)
        body_text = response.get_data(as_text=True)
        parsed = json.loads(body_text)
        self.assertIsInstance(parsed, dict)
        self.assertTrue(parsed.get("ok"))
        self.assertIn("city", parsed)
        self.assertIn("items", parsed)
        self.assertIsInstance(parsed["items"], list)
        return parsed

    def test_public_listings_recommended_json_contract(self):
        parsed = self._assert_discovery_shape("/api/public/listings/recommended?limit=5")
        self.assertTrue(parsed["items"], "expected at least one listing item for contract validation")
        for item in parsed["items"]:
            self.assertIsInstance(item, dict)
            self.assertTrue(LISTING_KEYS.issubset(item.keys()))
            self.assertIsInstance(item["ranking_reason"], list)

    def test_public_listings_search_json_contract(self):
        parsed = self._assert_discovery_shape("/api/public/listings/search?q=contract&limit=5")
        self.assertTrue(parsed["items"], "expected at least one listing search item for contract validation")
        for item in parsed["items"]:
            self.assertIsInstance(item, dict)
            self.assertTrue(LISTING_KEYS.issubset(item.keys()))
            self.assertIsInstance(item["ranking_reason"], list)

    def test_public_shortlets_recommended_json_contract(self):
        parsed = self._assert_discovery_shape("/api/public/shortlets/recommended?limit=5")
        self.assertTrue(parsed["items"], "expected at least one shortlet item for contract validation")
        for item in parsed["items"]:
            self.assertIsInstance(item, dict)
            self.assertTrue(SHORTLET_KEYS.issubset(item.keys()))
            self.assertIsInstance(item["ranking_reason"], list)


if __name__ == "__main__":
    unittest.main()
