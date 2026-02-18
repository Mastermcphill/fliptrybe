from __future__ import annotations

import unittest

from app import create_app
from app.extensions import db
from app.models import Category, User
from app.utils.jwt_utils import create_token


def _upsert_category(*, name: str, slug: str, parent_id: int | None = None) -> Category:
    row = Category.query.filter_by(slug=slug).first()
    if row is None:
        row = Category(name=name, slug=slug, parent_id=parent_id)
        db.session.add(row)
        db.session.flush()
        return row
    row.name = name
    row.parent_id = parent_id
    db.session.add(row)
    db.session.flush()
    return row


def _upsert_user(*, email: str, phone: str, role: str) -> User:
    row = User.query.filter_by(email=email).first()
    if row is None:
        row = User(name=email.split("@")[0], email=email, phone=phone, role=role, is_verified=True)
        row.set_password("password123")
        db.session.add(row)
        db.session.flush()
    row.role = role
    row.is_verified = True
    db.session.add(row)
    db.session.flush()
    return row


class VehicleEnergyVerticalsTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()

            merchant = _upsert_user(
                email="vertical-merchant@fliptrybe.dev",
                phone="2348100000002",
                role="merchant",
            )
            admin = _upsert_user(
                email="vertical-admin@fliptrybe.dev",
                phone="2348100000003",
                role="admin",
            )

            vehicles = _upsert_category(name="Vehicles", slug="vehicles", parent_id=None)
            cars = _upsert_category(name="Cars", slug="cars", parent_id=int(vehicles.id))
            power_energy = _upsert_category(name="Power & Energy", slug="power-energy", parent_id=None)
            solar_bundle = _upsert_category(name="Solar Bundle", slug="solar-bundle", parent_id=int(power_energy.id))

            db.session.commit()
            cls.merchant_token = create_token(int(merchant.id))
            cls.admin_token = create_token(int(admin.id))
            cls.cars_category_id = int(cars.id)
            cls.bundle_category_id = int(solar_bundle.id)

        cls.client = cls.app.test_client()

    def _merchant_headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.merchant_token}"}

    def _admin_headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.admin_token}"}

    def _customer_payout_profile(self) -> dict[str, str]:
        return {
            "customer_full_name": "Vertical Test Customer",
            "customer_address": "12 Admiralty Way, Lekki",
            "customer_phone": "08031112222",
            "bank_name": "Access Bank",
            "bank_account_number": "0123456789",
            "bank_account_name": "Vertical Test Customer",
        }

    def _create_vehicle_listing(self, *, title: str) -> int:
        res = self.client.post(
            "/api/listings",
            headers=self._merchant_headers(),
            json={
                "title": title,
                "description": "Vehicle listing test",
                "price": 8500000,
                "category": "Cars",
                "category_id": self.cars_category_id,
                "listing_type": "vehicle",
                "customer_payout_profile": self._customer_payout_profile(),
                "vehicle_metadata": {
                    "make": "Toyota",
                    "model": "Corolla",
                    "year_of_manufacture": 2019,
                    "condition": "Used - Good",
                    "transmission": "Automatic",
                    "fuel_type": "Petrol",
                    "drivetrain": "FWD",
                    "body_type": "Sedan",
                    "mileage": 62000,
                    "color": "Black",
                    "registered_car": True,
                    "accident_history": "None",
                    "service_history_available": True,
                    "location_verification_badge": True,
                    "inspection_request_option": True,
                    "delivery_available": True,
                    "financing_option": False,
                },
            },
        )
        self.assertEqual(res.status_code, 201)
        payload = res.get_json() or {}
        listing = payload.get("listing") or {}
        self.assertEqual((listing.get("listing_type") or "").lower(), "vehicle")
        self.assertEqual((listing.get("approval_status") or "").lower(), "pending")
        return int(listing.get("id") or 0)

    def test_schema_endpoints_return_vehicle_energy_and_real_estate_definitions(self):
        cars_schema = self.client.get("/api/public/categories/form-schema?category=Cars")
        self.assertEqual(cars_schema.status_code, 200)
        cars_payload = cars_schema.get_json() or {}
        cars = cars_payload.get("schema") or {}
        self.assertEqual(cars.get("metadata_key"), "vehicle_metadata")
        self.assertEqual((cars.get("listing_type_hint") or "").lower(), "vehicle")

        bundle_schema = self.client.get("/api/public/categories/form-schema?category=Solar%20Bundle")
        self.assertEqual(bundle_schema.status_code, 200)
        bundle_payload = bundle_schema.get_json() or {}
        bundle = bundle_payload.get("schema") or {}
        self.assertEqual(bundle.get("metadata_key"), "energy_metadata")
        self.assertEqual((bundle.get("listing_type_hint") or "").lower(), "energy")

        estate_schema = self.client.get("/api/public/categories/form-schema?category=House%20for%20Rent")
        self.assertEqual(estate_schema.status_code, 200)
        estate_payload = estate_schema.get_json() or {}
        estate = estate_payload.get("schema") or {}
        self.assertEqual(estate.get("metadata_key"), "real_estate_metadata")
        self.assertEqual((estate.get("listing_type_hint") or "").lower(), "real_estate")

    def test_vehicle_metadata_required_validation(self):
        res = self.client.post(
            "/api/listings",
            headers=self._merchant_headers(),
            json={
                "title": "Vehicle Invalid Meta",
                "description": "Missing required cars metadata",
                "price": 5000000,
                "category": "Cars",
                "category_id": self.cars_category_id,
                "listing_type": "vehicle",
                "customer_payout_profile": self._customer_payout_profile(),
                "vehicle_metadata": {"make": "Toyota"},
            },
        )
        self.assertEqual(res.status_code, 400)
        payload = res.get_json() or {}
        self.assertFalse(payload.get("ok", False))
        self.assertEqual(payload.get("error"), "VALIDATION_FAILED")

    def test_vehicle_filters_require_admin_approval_for_public_visibility(self):
        listing_id = self._create_vehicle_listing(title="Vehicle Approval Flow")

        before = self.client.get(
            "/api/public/listings/search?listing_type=vehicle&make=Toyota&model=Corolla&year=2019&limit=20"
        )
        self.assertEqual(before.status_code, 200)
        before_payload = before.get_json() or {}
        before_items = before_payload.get("items") or []
        self.assertFalse(any(int(item.get("id") or 0) == listing_id for item in before_items))

        approve_res = self.client.post(
            f"/api/admin/listings/{listing_id}/approve",
            headers=self._admin_headers(),
            json={"approved": True},
        )
        self.assertEqual(approve_res.status_code, 200)
        approve_payload = approve_res.get_json() or {}
        approved_listing = approve_payload.get("listing") or {}
        self.assertEqual((approved_listing.get("approval_status") or "").lower(), "approved")

        after = self.client.get(
            "/api/public/listings/search?listing_type=vehicle&make=Toyota&model=Corolla&year=2019&limit=20"
        )
        self.assertEqual(after.status_code, 200)
        after_payload = after.get_json() or {}
        after_items = after_payload.get("items") or []
        self.assertTrue(any(int(item.get("id") or 0) == listing_id for item in after_items))

    def test_energy_bundle_metadata_and_filters(self):
        res = self.client.post(
            "/api/listings",
            headers=self._merchant_headers(),
            json={
                "title": "Solar Bundle Vertical",
                "description": "5kVA complete solar bundle",
                "price": 2500000,
                "category": "Solar Bundle",
                "category_id": self.bundle_category_id,
                "customer_payout_profile": self._customer_payout_profile(),
                "energy_metadata": {
                    "inverter_brand_capacity": "Inverex 5kVA",
                    "battery_type": "Lithium",
                    "battery_capacity_ah": 200,
                    "number_of_batteries": 4,
                    "solar_panel_wattage": 550,
                    "number_of_panels": 8,
                    "included_accessories": "Cables, rails, breakers",
                    "installation_included": True,
                    "warranty_length": "24 months",
                    "load_capacity": "2 ACs, lights, fridge",
                    "estimated_daily_output": "16kWh",
                    "delivery_included": True,
                    "financing_option": True,
                },
            },
        )
        self.assertEqual(res.status_code, 201)
        payload = res.get_json() or {}
        listing = payload.get("listing") or {}
        listing_id = int(listing.get("id") or 0)
        self.assertEqual((listing.get("listing_type") or "").lower(), "energy")
        self.assertTrue(listing.get("bundle_badge"))
        self.assertEqual((listing.get("battery_type") or "").lower(), "lithium")
        self.assertTrue(bool(listing.get("lithium_only")))

        filtered = self.client.get(
            "/api/public/listings/search?battery_type=Lithium&inverter_capacity=Inverex 5kVA&lithium_only=1&limit=20"
        )
        self.assertEqual(filtered.status_code, 200)
        filtered_payload = filtered.get_json() or {}
        items = filtered_payload.get("items") or []
        self.assertTrue(any(int(item.get("id") or 0) == listing_id for item in items))

        flag_res = self.client.post(
            f"/api/admin/listings/{listing_id}/inspection-flag",
            headers=self._admin_headers(),
            json={"flagged": True},
        )
        self.assertEqual(flag_res.status_code, 200)
        flag_payload = flag_res.get_json() or {}
        flagged_listing = flag_payload.get("listing") or {}
        self.assertTrue(flagged_listing.get("inspection_flagged"))
        self.assertTrue(flagged_listing.get("inspection_required"))


if __name__ == "__main__":
    unittest.main()
