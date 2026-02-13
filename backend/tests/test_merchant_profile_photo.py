import unittest

from app import create_app
from app.extensions import db
from app.models import MerchantProfile, User
from app.utils.jwt_utils import create_token


class MerchantProfilePhotoTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
            user = User.query.filter(User.email == "merchant-photo-test@fliptrybe.dev").first()
            if user is None:
                user = User(
                    name="Merchant Photo Test",
                    email="merchant-photo-test@fliptrybe.dev",
                    phone="2348100000001",
                    role="merchant",
                )
                user.set_password("password123")
                db.session.add(user)
                db.session.flush()
            profile = MerchantProfile.query.filter_by(user_id=int(user.id)).first()
            if profile is None:
                profile = MerchantProfile(user_id=int(user.id), shop_name="Photo Merchant")
                db.session.add(profile)
            else:
                profile.shop_name = "Photo Merchant"
            db.session.commit()
            cls.user_id = int(user.id)
            cls.token = create_token(int(user.id))
        cls.client = cls.app.test_client()

    def test_upload_and_read_profile_photo(self):
        image_url = "https://res.cloudinary.com/demo/image/upload/v1/merchant-photo-test.jpg"
        res = self.client.post(
            "/api/me/profile/photo",
            headers={"Authorization": f"Bearer {self.token}"},
            json={"profile_image_url": image_url},
        )
        self.assertEqual(res.status_code, 200)
        body = res.get_json()
        self.assertTrue(body.get("ok"))
        self.assertEqual(body.get("profile_image_url"), image_url)

        public_res = self.client.get(f"/api/public/merchants/{self.user_id}")
        self.assertEqual(public_res.status_code, 200)
        public_body = public_res.get_json()
        self.assertTrue(public_body.get("ok"))
        merchant = public_body.get("merchant") or {}
        self.assertEqual(int(merchant.get("id") or 0), self.user_id)
        self.assertEqual((merchant.get("profile_image_url") or ""), image_url)


if __name__ == "__main__":
    unittest.main()
