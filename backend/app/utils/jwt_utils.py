import os
import time
import logging
from typing import Optional, Dict, Any, Tuple

import jwt

logger = logging.getLogger(__name__)


def _secret() -> str:
    return os.getenv("SECRET_KEY") or "dev-secret-change-me"


def create_access_token(user_id: int, ttl_seconds: int = 60 * 60 * 24 * 7) -> str:
    now = int(time.time())
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + ttl_seconds,
        "type": "access",
    }
    return jwt.encode(payload, _secret(), algorithm="HS256")


# Backward-compatible alias used by your auth routes.
def create_token(user_id: int, ttl_seconds: int = 60 * 60 * 24 * 7) -> str:
    return create_access_token(user_id=user_id, ttl_seconds=ttl_seconds)


def decode_token(token: str) -> Optional[Dict[str, Any]]:
    try:
        payload = jwt.decode(token, _secret(), algorithms=["HS256"])
        return payload
    except Exception:
        return None


def parse_auth_header(auth_header: str) -> Tuple[Optional[str], Optional[str]]:
    if not auth_header:
        return None, None
    parts = auth_header.split()
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1], "bearer"
    if len(parts) == 2 and parts[0].lower() == "token":
        try:
            logger.warning("Deprecated auth scheme Token used")
        except Exception:
            pass
        return parts[1], "token"
    return None, None


def get_bearer_token(auth_header: str) -> Optional[str]:
    if not auth_header:
        return None
    token, _scheme = parse_auth_header(auth_header)
    return token
