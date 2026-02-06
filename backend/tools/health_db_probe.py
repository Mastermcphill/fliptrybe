import os
from sqlalchemy import text
from sqlalchemy.engine.url import make_url

from app import create_app
from app.extensions import db


def _safe_uri(uri: str) -> str:
    if not uri:
        return "unknown"
    try:
        return make_url(uri).render_as_string(hide_password=True)
    except Exception:
        return "unknown"


def main():
    app = create_app()
    with app.app_context():
        uri = app.config.get("SQLALCHEMY_DATABASE_URI") or ""
        print("SQLALCHEMY_DATABASE_URI:", _safe_uri(uri))
        try:
            with db.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            print("SELECT 1: success")
        except Exception as e:
            print("SELECT 1: fail")
            msg = str(e)
            if msg:
                msg = (msg[:300] + "...") if len(msg) > 300 else msg
                print("error:", msg)


if __name__ == "__main__":
    main()
