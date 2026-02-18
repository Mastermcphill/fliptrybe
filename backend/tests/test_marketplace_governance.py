from __future__ import annotations

import os
import unittest

from app import create_app
from app.extensions import db
from app.models import Category, Listing, User
from app.utils.jwt_utils import create_token


def _upsert_user(*, email: str, phone: str, role: str, verified: bool = True) -> User:
    row = User.query.filter_by(email=email).first()
    if row is None:
        row = User(
            name=email.split("@")[0],
            email=email,
            phone=phone,
            role=role,
            is_verified=verified,
        )
        row.set_password("password123")
        db.session.add(row)
        db.session.flush()
    row.role = role
    row.phone = phone
    row.is_verified = verified
    db.session.add(row)
    db.session.flush()
    return row


def _upsert_category(*, name: str, slug: str, parent_id: int | None = None) -> Category:
    row = Category.query.filter_by(slug=slug).first()
    if row is None:
        row = Category(name=name, slug=slug, parent_id=parent_id)
        db.session.add(row)
        db.session.flush()
    row.name = name
    row.parent_id = parent_id
    db.session.add(row)
    db.session.flush()
    return row


class MarketplaceGovernanceTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._prev_db_uri = os.getenv("SQLALCHEMY_DATABASE_URI")
        cls._prev_db_url = os.getenv("DATABASE_URL")
        db_uri = "sqlite:///:memory:"
        os.environ["SQLALCHEMY_DATABASE_URI"] = db_uri
        os.environ["DATABASE_URL"] = db_uri

        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()

            cls.buyer = _upsert_user(
                email="gov-buyer@fliptrybe.dev",
                phone="2348101001001",
                role="buyer",
                verified=False,
            )
            cls.merchant = _upsert_user(
                email="gov-merchant@fliptrybe.dev",
                phone="2348101001002",
                role="merchant",
                verified=False,
            )
            cls.admin = _upsert_user(
                email="gov-admin@fliptrybe.dev",
                phone="2348101001003",
                role="admin",
                verified=True,
            )
            cls.search_user = _upsert_user(
                email="gov-search@fliptrybe.dev",
                phone="2348101001004",
                role="buyer",
                verified=True,
            )

            real_estate = _upsert_category(name="Real Estate", slug="real-estate", parent_id=None)
            house_for_rent = _upsert_category(
                name="House for Rent",
                slug="house-for-rent",
                parent_id=int(real_estate.id),
            )
            _upsert_category(
                name="House for Sale",
                slug="house-for-sale",
                parent_id=int(real_estate.id),
            )
            _upsert_category(
                name="Land for Sale",
                slug="land-for-sale",
                parent_id=int(real_estate.id),
            )

            db.session.commit()

            cls.buyer_token = create_token(int(cls.buyer.id))
            cls.merchant_token = create_token(int(cls.merchant.id))
            cls.admin_token = create_token(int(cls.admin.id))
            cls.search_user_token = create_token(int(cls.search_user.id))
            cls.house_for_rent_category_id = int(house_for_rent.id)

        cls.client = cls.app.test_client()

    @classmethod
    def tearDownClass(cls):
        if cls._prev_db_uri is None:
            os.environ.pop("SQLALCHEMY_DATABASE_URI", None)
        else:
            os.environ["SQLALCHEMY_DATABASE_URI"] = cls._prev_db_uri
        if cls._prev_db_url is None:
            os.environ.pop("DATABASE_URL", None)
        else:
            os.environ["DATABASE_URL"] = cls._prev_db_url

    def _headers(self, token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

    def test_listing_description_blocks_contact_details(self):
        res = self.client.post(
            "/api/listings",
            headers=self._headers(self.buyer_token),
            json={
                "title": "Blocked Contact Description",
                "description": "Call me on 08031234567 to buy now.",
                "price": 120000,
                "category": "General",
            },
        )
        self.assertEqual(res.status_code, 400)
        payload = res.get_json() or {}
        self.assertEqual(payload.get("error"), "DESCRIPTION_CONTACT_BLOCKED")

    def test_merchant_listing_requires_customer_payout_profile(self):
        res = self.client.post(
            "/api/listings",
            headers=self._headers(self.merchant_token),
            json={
                "title": "Merchant Missing Customer Profile",
                "description": "Valid description without contact details.",
                "price": 500000,
                "category": "General",
            },
        )
        self.assertEqual(res.status_code, 400)
        payload = res.get_json() or {}
        self.assertEqual(payload.get("error"), "CUSTOMER_PAYOUT_PROFILE_REQUIRED")

    def test_buyer_listing_does_not_require_customer_profile(self):
        res = self.client.post(
            "/api/listings",
            headers=self._headers(self.buyer_token),
            json={
                "title": "Buyer Listing Works",
                "description": "Buyer listing without payout profile.",
                "price": 90000,
                "category": "General",
            },
        )
        self.assertEqual(res.status_code, 201)
        payload = res.get_json() or {}
        self.assertTrue(payload.get("ok"))

    def test_customer_payout_profile_is_private_and_admin_accessible(self):
        create_res = self.client.post(
            "/api/listings",
            headers=self._headers(self.merchant_token),
            json={
                "title": "Merchant Listing With Customer Profile",
                "description": "Ready for payout processing.",
                "price": 780000,
                "category": "General",
                "customer_payout_profile": {
                    "customer_full_name": "Jane Customer",
                    "customer_address": "14 Admiralty Way, Lekki",
                    "customer_phone": "08030001111",
                    "bank_name": "Access Bank",
                    "bank_account_number": "0123456789",
                    "bank_account_name": "Jane Customer",
                },
            },
        )
        self.assertEqual(create_res.status_code, 201)
        listing = (create_res.get_json() or {}).get("listing") or {}
        listing_id = int(listing.get("id") or 0)
        self.assertGreater(listing_id, 0)

        owner_detail = self.client.get(
            f"/api/listings/{listing_id}",
            headers=self._headers(self.merchant_token),
        )
        self.assertEqual(owner_detail.status_code, 200)
        owner_listing = (owner_detail.get_json() or {}).get("listing") or {}
        self.assertIn("customer_payout_profile", owner_listing)
        self.assertEqual(
            ((owner_listing.get("customer_payout_profile") or {}).get("bank_account_number") or ""),
            "0123456789",
        )

        public_detail = self.client.get(
            f"/api/listings/{listing_id}",
            headers=self._headers(self.buyer_token),
        )
        self.assertEqual(public_detail.status_code, 200)
        public_listing = (public_detail.get_json() or {}).get("listing") or {}
        self.assertNotIn("customer_payout_profile", public_listing)

        admin_detail = self.client.get(
            f"/api/admin/listings/{listing_id}/customer-payout-profile",
            headers=self._headers(self.admin_token),
        )
        self.assertEqual(admin_detail.status_code, 200)
        admin_payload = admin_detail.get_json() or {}
        self.assertTrue(admin_payload.get("ok"))
        self.assertIn("copy_text", admin_payload)
        self.assertIn("Jane Customer", (admin_payload.get("copy_text") or ""))

    def test_saved_searches_crud_and_limit(self):
        token_headers = self._headers(self.search_user_token)

        created_ids: list[int] = []
        for idx in range(20):
            res = self.client.post(
                "/api/saved-searches",
                headers=token_headers,
                json={
                    "name": f"Preset {idx + 1}",
                    "vertical": "real_estate" if idx % 2 == 0 else "vehicles",
                    "query_json": {"query": f"q-{idx}", "minPrice": idx * 1000},
                },
            )
            self.assertEqual(res.status_code, 201)
            item = (res.get_json() or {}).get("item") or {}
            created_ids.append(int(item.get("id") or 0))

        limit_res = self.client.post(
            "/api/saved-searches",
            headers=token_headers,
            json={"name": "Overflow", "vertical": "vehicles", "query_json": {"query": "overflow"}},
        )
        self.assertEqual(limit_res.status_code, 400)
        self.assertEqual((limit_res.get_json() or {}).get("error"), "SAVED_SEARCH_LIMIT_REACHED")

        target_id = created_ids[0]
        update_res = self.client.put(
            f"/api/saved-searches/{target_id}",
            headers=token_headers,
            json={"name": "Vehicles Fast Filter", "vertical": "vehicles"},
        )
        self.assertEqual(update_res.status_code, 200)
        updated = (update_res.get_json() or {}).get("item") or {}
        self.assertEqual(updated.get("name"), "Vehicles Fast Filter")

        use_res = self.client.post(
            f"/api/saved-searches/{target_id}/use",
            headers=token_headers,
            json={},
        )
        self.assertEqual(use_res.status_code, 200)
        self.assertTrue(((use_res.get_json() or {}).get("item") or {}).get("last_used_at"))

        list_res = self.client.get("/api/saved-searches?vertical=vehicles", headers=token_headers)
        self.assertEqual(list_res.status_code, 200)
        items = (list_res.get_json() or {}).get("items") or []
        self.assertTrue(any(int(item.get("id") or 0) == target_id for item in items))

        delete_res = self.client.delete(f"/api/saved-searches/{target_id}", headers=token_headers)
        self.assertEqual(delete_res.status_code, 200)
        self.assertTrue((delete_res.get_json() or {}).get("deleted"))

    def test_real_estate_schema_and_filters(self):
        schema = self.client.get("/api/public/categories/form-schema?category=House%20for%20Rent")
        self.assertEqual(schema.status_code, 200)
        schema_payload = schema.get_json() or {}
        schema_obj = schema_payload.get("schema") or {}
        self.assertEqual(schema_obj.get("metadata_key"), "real_estate_metadata")
        fields = schema_obj.get("fields") or []
        keys = {str(field.get("key") or "") for field in fields if isinstance(field, dict)}
        self.assertIn("bedrooms", keys)
        self.assertIn("bathrooms", keys)

        create_res = self.client.post(
            "/api/listings",
            headers=self._headers(self.buyer_token),
            json={
                "title": "Lekki 3-Bedroom Serviced Apartment",
                "description": "Clean apartment with serviced facilities.",
                "price": 4200000,
                "category": "House for Rent",
                "category_id": self.house_for_rent_category_id,
                "listing_type": "real_estate",
                "state": "Lagos",
                "city": "Lekki",
                "locality": "Lekki Phase 1",
                "real_estate_metadata": {
                    "property_type": "Rent",
                    "state": "Lagos",
                    "city": "Lekki",
                    "area": "Lekki Phase 1",
                    "price": 4200000,
                    "title_headline": "3-bedroom serviced rent",
                    "description": "Serviced apartment with parking",
                    "bedrooms": 3,
                    "bathrooms": 3,
                    "toilets": 4,
                    "parking_spaces": 2,
                    "furnished": True,
                    "serviced": True,
                    "newly_built": False,
                },
            },
        )
        self.assertEqual(create_res.status_code, 201)
        listing = (create_res.get_json() or {}).get("listing") or {}
        listing_id = int(listing.get("id") or 0)
        self.assertGreater(listing_id, 0)
        self.assertEqual((listing.get("listing_type") or "").lower(), "real_estate")

        search = self.client.get(
            "/api/public/listings/search?"
            "listing_type=real_estate&property_type=Rent&bedrooms_min=3&bathrooms_min=3"
            "&furnished=1&serviced=1&state=Lagos&city=Lekki&limit=20"
        )
        self.assertEqual(search.status_code, 200)
        items = (search.get_json() or {}).get("items") or []
        self.assertTrue(any(int(item.get("id") or 0) == listing_id for item in items))

    def test_chat_blocks_contact_exchange_and_allows_normal_enquiry(self):
        blocked = self.client.post(
            "/api/support/messages",
            headers=self._headers(self.buyer_token),
            json={
                "user_id": int(self.merchant.id),
                "body": "WhatsApp me on wa.me/2348012345678",
            },
        )
        self.assertEqual(blocked.status_code, 400)
        blocked_payload = blocked.get_json() or {}
        self.assertEqual(blocked_payload.get("error"), "CONTACT_BLOCKED")

        allowed = self.client.post(
            "/api/support/messages",
            headers=self._headers(self.buyer_token),
            json={
                "user_id": int(self.merchant.id),
                "body": "Is this listing still available, and can it be inspected?",
            },
        )
        self.assertEqual(allowed.status_code, 201)
        allowed_payload = allowed.get_json() or {}
        self.assertTrue(allowed_payload.get("ok"))


if __name__ == "__main__":
    unittest.main()

