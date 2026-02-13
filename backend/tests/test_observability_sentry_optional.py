from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from flask import Flask

from app.utils.observability import init_sentry


class SentryOptionalInitTestCase(unittest.TestCase):
    def test_sentry_init_is_noop_without_dsn(self):
        app = Flask(__name__)
        with patch.dict(os.environ, {"SENTRY_DSN": ""}, clear=False):
            init_sentry(app)


if __name__ == "__main__":
    unittest.main()
