from __future__ import annotations

import base64
import io
from urllib.parse import urlparse

import imagehash
import requests
from PIL import Image


def compute_phash64(image_bytes: bytes) -> int:
    """Compute 64-bit perceptual hash from decoded pixels."""
    with Image.open(io.BytesIO(image_bytes)) as img:
        rgb = img.convert("RGB")
        ph = imagehash.phash(rgb, hash_size=8)
    return int(str(ph), 16)


def hamming_distance(a: int, b: int) -> int:
    return int((int(a) ^ int(b)).bit_count())


def hash_to_hex(value: int) -> str:
    return f"{int(value) & ((1 << 64) - 1):016x}"


def parse_cloudinary_public_id(url: str) -> str:
    raw = (url or "").strip()
    if not raw:
        return ""
    parsed = urlparse(raw)
    host = (parsed.netloc or "").lower()
    if "cloudinary.com" not in host:
        return ""
    path = (parsed.path or "").strip("/")
    if "/upload/" not in path:
        return ""
    tail = path.split("/upload/", 1)[-1]
    parts = [p for p in tail.split("/") if p]
    if not parts:
        return ""
    # Trim optional version segment.
    if parts and parts[0].startswith("v") and parts[0][1:].isdigit():
        parts = parts[1:]
    if not parts:
        return ""
    final = "/".join(parts)
    if "." in final:
        final = final.rsplit(".", 1)[0]
    return final[:255]


def bytes_from_data_uri(data_uri: str) -> bytes:
    if not data_uri.startswith("data:"):
        raise ValueError("not_data_uri")
    marker = ";base64,"
    idx = data_uri.find(marker)
    if idx < 0:
        raise ValueError("unsupported_data_uri")
    encoded = data_uri[idx + len(marker) :]
    return base64.b64decode(encoded)


def fetch_image_bytes(url: str, *, timeout_seconds: int = 8) -> bytes:
    response = requests.get(url, timeout=timeout_seconds)
    response.raise_for_status()
    return bytes(response.content or b"")

