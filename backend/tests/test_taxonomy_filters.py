from datetime import datetime
import unittest

from app import create_app
from app.extensions import db
from app.models import Brand, BrandModel, Category, Listing


class TaxonomyFiltersTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()

            parent = Category.query.filter_by(slug="phones-test").first()
            if parent is None:
                parent = Category(name="Phones Test", slug="phones-test")
                db.session.add(parent)
                db.session.flush()

            leaf = Category.query.filter_by(slug="iphone-13-test").first()
            if leaf is None:
                leaf = Category(
                    name="iPhone 13 Test",
                    slug="iphone-13-test",
                    parent_id=int(parent.id),
                )
                db.session.add(leaf)
                db.session.flush()

            brand = Brand.query.filter_by(slug="apple-test").first()
            if brand is None:
                brand = Brand(name="Apple Test", slug="apple-test", category_id=int(parent.id))
                db.session.add(brand)
                db.session.flush()

            model = BrandModel.query.filter_by(slug="apple-iphone-13-test").first()
            if model is None:
                model = BrandModel(
                    name="iPhone 13 Test",
                    slug="apple-iphone-13-test",
                    brand_id=int(brand.id),
                    category_id=int(parent.id),
                )
                db.session.add(model)
                db.session.flush()

            listing = Listing.query.filter(Listing.title == "Taxonomy Test Listing").first()
            if listing is None:
                listing = Listing(
                    title="Taxonomy Test Listing",
                    description="Taxonomy filter contract listing",
                    category="Phones",
                    category_id=int(leaf.id),
                    brand_id=int(brand.id),
                    model_id=int(model.id),
                    price=450000.0,
                    date_posted=datetime.utcnow(),
                    state="Lagos",
                    city="Ikeja",
                    locality="Computer Village",
                    image_path="",
                    is_active=True,
                )
                db.session.add(listing)
            else:
                listing.category_id = int(leaf.id)
                listing.brand_id = int(brand.id)
                listing.model_id = int(model.id)
                listing.is_active = True

            db.session.commit()
            cls.parent_id = int(parent.id)
            cls.leaf_id = int(leaf.id)
            cls.brand_id = int(brand.id)
            cls.model_id = int(model.id)

        cls.client = cls.app.test_client()

    def test_public_categories_returns_tree(self):
        res = self.client.get("/api/public/categories")
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertIsInstance(data, dict)
        self.assertTrue(data.get("ok"))
        self.assertIsInstance(data.get("items"), list)

    def test_public_filters_returns_brands_and_models(self):
        res = self.client.get(
            f"/api/public/filters?category_id={self.parent_id}&brand_id={self.brand_id}"
        )
        self.assertEqual(res.status_code, 200)
        data = res.get_json()
        self.assertTrue(data.get("ok"))
        self.assertIsInstance(data.get("brands"), list)
        self.assertIsInstance(data.get("models"), list)

    def test_search_supports_taxonomy_filters(self):
        by_leaf = self.client.get(f"/api/public/listings/search?category_id={self.leaf_id}&limit=20")
        self.assertEqual(by_leaf.status_code, 200)
        leaf_payload = by_leaf.get_json()
        self.assertTrue(leaf_payload.get("ok"))
        self.assertTrue(leaf_payload.get("items"))
        self.assertTrue(
            any((item.get("category_id") == self.leaf_id) for item in leaf_payload.get("items", []))
        )

        by_parent = self.client.get(
            f"/api/public/listings/search?parent_category_id={self.parent_id}&limit=20"
        )
        self.assertEqual(by_parent.status_code, 200)
        parent_payload = by_parent.get_json()
        self.assertTrue(parent_payload.get("ok"))
        self.assertTrue(parent_payload.get("items"))

        by_brand = self.client.get(f"/api/public/listings/search?brand_id={self.brand_id}&limit=20")
        self.assertEqual(by_brand.status_code, 200)
        brand_payload = by_brand.get_json()
        self.assertTrue(brand_payload.get("ok"))
        self.assertTrue(brand_payload.get("items"))

        by_model = self.client.get(f"/api/public/listings/search?model_id={self.model_id}&limit=20")
        self.assertEqual(by_model.status_code, 200)
        model_payload = by_model.get_json()
        self.assertTrue(model_payload.get("ok"))
        self.assertTrue(model_payload.get("items"))


if __name__ == "__main__":
    unittest.main()
