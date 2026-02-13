from __future__ import annotations

import os
from dataclasses import dataclass

from sqlalchemy.exc import IntegrityError

from app.extensions import db
from app.models import ImageFingerprint
from app.utils.image_fingerprint import (
    bytes_from_data_uri,
    compute_phash64,
    fetch_image_bytes,
    hamming_distance,
    hash_to_hex,
    parse_cloudinary_public_id,
)


@dataclass
class DuplicateImageError(Exception):
    code: str
    message: str
    duplicate_fingerprint_id: int | None = None
    distance: int | None = None

    def to_payload(self) -> dict:
        payload = {
            "ok": False,
            "code": self.code,
            "message": self.message,
        }
        if self.duplicate_fingerprint_id is not None:
            payload["duplicate_fingerprint_id"] = int(self.duplicate_fingerprint_id)
        if self.distance is not None:
            payload["distance"] = int(self.distance)
        return payload


def _near_threshold() -> int:
    raw = (os.getenv("IMAGE_DEDUPE_THRESHOLD") or "").strip()
    try:
        val = int(raw)
    except Exception:
        val = 6
    return max(1, min(val, 16))


def _near_scan_limit() -> int:
    raw = (os.getenv("IMAGE_DEDUPE_SCAN_LIMIT") or "").strip()
    try:
        val = int(raw)
    except Exception:
        val = 50000
    return max(100, min(val, 200000))


def _to_signed_64(value: int) -> int:
    raw = int(value) & ((1 << 64) - 1)
    if raw >= (1 << 63):
        return raw - (1 << 64)
    return raw


def _to_unsigned_64(value: int) -> int:
    return int(value) & ((1 << 64) - 1)


def _resolve_local_upload_bytes(image_ref: str, *, upload_dir: str) -> bytes | None:
    ref = (image_ref or "").strip()
    if not ref:
        return None
    normalized = ref.replace("\\", "/")
    name = ""
    if normalized.startswith("/api/uploads/"):
        name = normalized.split("/api/uploads/", 1)[-1]
    elif normalized.startswith("/api/shortlet_uploads/"):
        name = normalized.split("/api/shortlet_uploads/", 1)[-1]
    if not name:
        if os.path.isfile(normalized):
            with open(normalized, "rb") as fh:
                return fh.read()
        return None
    path = os.path.abspath(os.path.join(upload_dir, name))
    if not path.startswith(os.path.abspath(upload_dir)):
        return None
    if not os.path.isfile(path):
        return None
    with open(path, "rb") as fh:
        return fh.read()


def _load_bytes(*, image_bytes: bytes | None, image_url: str, upload_dir: str) -> bytes:
    if image_bytes:
        return image_bytes
    ref = (image_url or "").strip()
    if not ref:
        raise ValueError("image_source_required")
    if ref.startswith("data:"):
        return bytes_from_data_uri(ref)
    local = _resolve_local_upload_bytes(ref, upload_dir=upload_dir)
    if local:
        return local
    return fetch_image_bytes(ref)


def ensure_image_unique(
    *,
    image_url: str = "",
    image_bytes: bytes | None = None,
    source: str = "unknown",
    uploader_user_id: int | None = None,
    listing_id: int | None = None,
    shortlet_id: int | None = None,
    allow_same_entity: bool = False,
    upload_dir: str = "",
) -> ImageFingerprint:
    content = _load_bytes(image_bytes=image_bytes, image_url=image_url, upload_dir=upload_dir)
    phash_int = compute_phash64(content)
    phash_hex = hash_to_hex(phash_int)

    existing = ImageFingerprint.query.filter_by(hash_hex=phash_hex).first()
    if existing:
        same_listing = listing_id is not None and int(existing.listing_id or 0) == int(listing_id or 0)
        same_shortlet = shortlet_id is not None and int(existing.shortlet_id or 0) == int(shortlet_id or 0)
        if allow_same_entity and (same_listing or same_shortlet):
            return existing
        raise DuplicateImageError(
            code="DUPLICATE_IMAGE",
            message="This image has already been used in another listing.",
            duplicate_fingerprint_id=int(existing.id),
            distance=0,
        )

    threshold = _near_threshold()
    limit = _near_scan_limit()
    candidates = (
        ImageFingerprint.query.with_entities(
            ImageFingerprint.id,
            ImageFingerprint.hash_int,
            ImageFingerprint.listing_id,
            ImageFingerprint.shortlet_id,
        )
        .order_by(ImageFingerprint.id.desc())
        .limit(limit)
        .all()
    )
    for cand_id, cand_hash, cand_listing_id, cand_shortlet_id in candidates:
        if cand_hash is None:
            continue
        if allow_same_entity:
            if listing_id is not None and int(cand_listing_id or 0) == int(listing_id or 0):
                continue
            if shortlet_id is not None and int(cand_shortlet_id or 0) == int(shortlet_id or 0):
                continue
        dist = hamming_distance(phash_int, _to_unsigned_64(int(cand_hash)))
        if dist <= threshold:
            raise DuplicateImageError(
                code="DUPLICATE_IMAGE_SIMILAR",
                message="This photo is too similar to one already used on FlipTrybe.",
                duplicate_fingerprint_id=int(cand_id),
                distance=int(dist),
            )

    item = ImageFingerprint(
        hash_type="phash64",
        hash_hex=phash_hex,
        hash_int=_to_signed_64(phash_int),
        source=(source or "unknown").strip()[:32] or "unknown",
        cloudinary_public_id=parse_cloudinary_public_id(image_url),
        image_url=(image_url or "")[:1024],
        listing_id=int(listing_id) if listing_id is not None else None,
        shortlet_id=int(shortlet_id) if shortlet_id is not None else None,
        uploader_user_id=int(uploader_user_id) if uploader_user_id is not None else None,
    )
    try:
        with db.session.begin_nested():
            db.session.add(item)
            db.session.flush()
        return item
    except IntegrityError:
        existing = ImageFingerprint.query.filter_by(hash_hex=phash_hex).first()
        raise DuplicateImageError(
            code="DUPLICATE_IMAGE",
            message="This image has already been used in another listing.",
            duplicate_fingerprint_id=int(existing.id) if existing else None,
            distance=0,
        )
