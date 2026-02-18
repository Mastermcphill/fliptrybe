from __future__ import annotations

import io
import os
import time
import unittest

from PIL import Image, ImageDraw

from app import create_app
from app.extensions import db
from app.models import User, Listing, ImageFingerprint
from app.utils.image_fingerprint import compute_phash64, hamming_distance
from app.utils.jwt_utils import create_access_token


class ImageFingerprintDedupeTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ["IMAGE_DEDUPE_THRESHOLD"] = "16"
        os.environ["IMAGE_DEDUPE_SCAN_LIMIT"] = "50000"
        cls._prev_db_uri = os.getenv("SQLALCHEMY_DATABASE_URI")
        cls._prev_db_url = os.getenv("DATABASE_URL")
        db_uri = "sqlite:///:memory:"
        os.environ["SQLALCHEMY_DATABASE_URI"] = db_uri
        os.environ["DATABASE_URL"] = db_uri
        cls.app = create_app()
        cls.app.config.update(TESTING=True)
        with cls.app.app_context():
            db.create_all()
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

    def _auth_headers(self) -> dict[str, str]:
        suffix = str(int(time.time() * 1000000))
        with self.app.app_context():
            user = User(
                name="Image Tester",
                email=f"img-{suffix}@fliptrybe.test",
                phone=f"090{suffix[-8:]}",
                role="buyer",
                is_verified=True,
            )
            user.set_password("Passw0rd!")
            db.session.add(user)
            db.session.commit()
            token = create_access_token(int(user.id))
        return {"Authorization": f"Bearer {token}"}

    def setUp(self):
        with self.app.app_context():
            db.session.query(ImageFingerprint).delete()
            db.session.query(Listing).delete()
            db.session.commit()

    def _png_bytes(self, image: Image.Image) -> bytes:
        buff = io.BytesIO()
        image.save(buff, format="PNG")
        return buff.getvalue()

    def _base_image(self, *, seed: int = 0) -> Image.Image:
        bg = (226 + (seed % 11), 230 - (seed % 7), 236 - (seed % 9))
        img = Image.new("RGB", (160, 160), color=bg)
        draw = ImageDraw.Draw(img)
        draw.rectangle((16, 18, 126, 116), fill=(48 + (seed % 23), 92, 188 - (seed % 17)))
        draw.ellipse((78, 72, 148, 142), fill=(214 - (seed % 19), 48 + (seed % 13), 72))
        draw.rectangle((30, 130, 120, 150), fill=(32 + (seed % 21), 32, 32))
        return img

    def _near_variant_bytes(self, base: Image.Image) -> bytes:
        base_hash = compute_phash64(self._png_bytes(base))
        candidates: list[Image.Image] = []
        for patch in (4, 6, 8, 10, 12, 14, 16):
            var = base.copy()
            draw = ImageDraw.Draw(var)
            draw.rectangle((0, 0, patch, patch), fill=(12, 12, 12))
            candidates.append(var)
        for ratio in (0.92, 0.88):
            w = max(32, int(base.width * ratio))
            h = max(32, int(base.height * ratio))
            var = base.resize((w, h), Image.Resampling.BICUBIC).resize(
                (base.width, base.height), Image.Resampling.BICUBIC
            )
            candidates.append(var)
        for var in candidates:
            raw = self._png_bytes(var)
            dist = hamming_distance(base_hash, compute_phash64(raw))
            if 1 <= dist <= 16:
                return raw
        # Guaranteed non-identical fallback.
        fallback = base.copy()
        draw = ImageDraw.Draw(fallback)
        draw.rectangle((0, 0, 20, 20), fill=(255, 255, 255))
        return self._png_bytes(fallback)

    def _create_listing(self, *, auth: dict[str, str], title: str, image_bytes: bytes):
        data = {
            "title": title,
            "description": "Image fingerprint test",
            "price": "15000",
            "state": "Lagos",
            "city": "Lagos",
            "image": (io.BytesIO(image_bytes), "photo.png"),
        }
        return self.client.post(
            "/api/listings",
            data=data,
            headers=auth,
            content_type="multipart/form-data",
        )

    def test_exact_duplicate_image_is_blocked(self):
        auth = self._auth_headers()
        base = self._base_image(seed=1)
        first = self._create_listing(auth=auth, title="Exact A", image_bytes=self._png_bytes(base))
        self.assertEqual(first.status_code, 201)

        second = self._create_listing(auth=auth, title="Exact B", image_bytes=self._png_bytes(base))
        self.assertEqual(second.status_code, 409)
        body = second.get_json(force=True)
        self.assertEqual(body.get("code"), "DUPLICATE_IMAGE")
        self.assertIn("trace_id", body)

    def test_near_duplicate_image_is_blocked(self):
        auth = self._auth_headers()
        base = self._base_image(seed=2)
        base_bytes = self._png_bytes(base)
        variant_bytes = self._near_variant_bytes(base)
        self.assertNotEqual(base_bytes, variant_bytes)

        first = self._create_listing(auth=auth, title="Near A", image_bytes=base_bytes)
        self.assertEqual(first.status_code, 201)

        second = self._create_listing(auth=auth, title="Near B", image_bytes=variant_bytes)
        self.assertEqual(second.status_code, 409)
        body = second.get_json(force=True)
        self.assertEqual(body.get("code"), "DUPLICATE_IMAGE_SIMILAR")
        self.assertIn("trace_id", body)

    def test_different_image_passes(self):
        auth = self._auth_headers()
        first = self._create_listing(auth=auth, title="Diff A", image_bytes=self._png_bytes(self._base_image(seed=3)))
        self.assertEqual(first.status_code, 201)

        other = Image.new("RGB", (160, 160), color=(32, 140, 90))
        draw = ImageDraw.Draw(other)
        draw.rectangle((20, 20, 140, 140), fill=(220, 220, 64))
        draw.line((0, 0, 160, 160), fill=(0, 0, 0), width=5)
        second = self._create_listing(auth=auth, title="Diff B", image_bytes=self._png_bytes(other))
        self.assertEqual(second.status_code, 201)


if __name__ == "__main__":
    unittest.main()
