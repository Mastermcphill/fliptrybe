from __future__ import annotations

from dataclasses import dataclass


@dataclass
class IntegrationResult:
    ok: bool
    code: str = ""
    message: str = ""
    raw: dict | None = None


class IntegrationDisabledError(RuntimeError):
    pass


class IntegrationMisconfiguredError(RuntimeError):
    pass

