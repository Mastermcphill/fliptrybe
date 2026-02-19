import os
import subprocess
import click
from pathlib import Path
from flask import Flask, jsonify, request, g
from sqlalchemy import text, inspect
from werkzeug.exceptions import HTTPException

from app.extensions import db, migrate, cors
from app.models import User
from app.segments.segment_09_users_auth_routes import auth_bp
from app.segments.segment_20_rides_routes import ride_bp
from app.segments.segment_payments import payments_bp, admin_payments_bp, public_payments_bp, admin_payment_intents_bp, payment_intents_bp
from app.segments.segment_payout_recipient import recipient_bp
from app.segments.segment_audit_admin import audit_bp
from app.segments.segment_reconciliation_admin import recon_bp
from app.segments.segment_merchant_dashboard import merchant_bp
from app.segments.segment_driver import drivers_bp
from app.segments.segment_driver_profile import driver_profile_bp
from app.segments.segment_kpis import kpi_bp
from app.segments.segment_notifications_queue import notify_bp
from app.segments.segment_admin import admin_bp
from app.segments.segment_market import market_bp
from app.segments.segment_shortlets import shortlets_bp
from app.segments.segment_wallets import wallets_bp
from app.segments.segment_commission_rules import commission_bp
from app.segments.segment_notification_queue import notifq_bp
from app.segments.segment_leaderboard import leader_bp
from app.segments.segment_wallet_analytics import analytics_bp
from app.segments.segment_payout_pdf import payout_pdf_bp
from app.segments.segment_autopilot import autopilot_bp, payments_settings_bp
from app.segments.segment_driver_availability import driver_avail_bp
from app.segments.segment_driver_offers import driver_offer_bp
from app.segments.segment_merchants import merchants_bp
from app.segments.segment_payment_webhooks import webhooks_bp
from app.segments.segment_notifications import notifications_bp
from app.segments.segment_receipts import receipts_bp
from app.segments.segment_admin_notifications import admin_notify_bp
from app.segments.segment_leaderboards import leaderboards_bp
from app.segments.segment_notification_dispatcher import dispatcher_bp
from app.segments.segment_support import support_bp
from app.segments.segment_support_chat import support_bp as support_chat_bp, support_admin_bp as support_chat_admin_bp
from app.segments.segment_inspector_requests import inspector_req_bp, inspector_req_admin_bp
from app.segments.segment_orders_api import orders_bp
from app.segments.segment_inspections_api import inspections_bp
from app.segments.segment_settings import settings_bp, preferences_bp
from app.segments.segment_kyc import kyc_bp
from app.segments.segment_drivers_list import drivers_list_bp
from app.segments.segment_merchant_follow import merchant_follow_bp
from app.segments.segment_inspector_bonds_admin import inspector_bonds_admin_bp
from app.segments.segment_role_change import role_change_bp
from app.segments.segment_moneybox import moneybox_bp, moneybox_system_bp
from app.segments.segment_public_feed import public_bp
from app.segments.segment_admin_ops import admin_ops_bp
from app.segments.segment_feature_flags import flags_bp
from app.segments.segment_referral import referral_bp
from app.segments.segment_user_analytics import user_analytics_bp
from app.segments.segment_pricing import pricing_bp
from app.segments.segment_omega_intelligence import omega_bp
from app.utils.jwt_utils import decode_token, get_bearer_token
from app.utils.autopilot import get_settings
from app.utils.observability import init_sentry, init_otel, install_request_observers
from app.utils.rate_limit import (
    check_limit,
    rate_limit_enabled,
    build_rate_limit_subject,
)


def _resolve_alembic_head() -> str:
    try:
        from alembic.config import Config
        from alembic.script import ScriptDirectory

        migrations_dir = Path(__file__).resolve().parents[1] / "migrations"
        cfg = Config(str(migrations_dir / "alembic.ini"))
        cfg.set_main_option("script_location", str(migrations_dir))
        script = ScriptDirectory.from_config(cfg)
        heads = script.get_heads()
        return heads[0] if heads else "unknown"
    except Exception:
        return "unknown"


def _resolve_git_sha() -> str:
    for env_key in ("RENDER_GIT_COMMIT", "GIT_SHA", "SOURCE_VERSION"):
        val = (os.getenv(env_key) or "").strip()
        if val:
            return val
    try:
        repo_root = Path(__file__).resolve().parents[1]
        out = subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=str(repo_root),
            stderr=subprocess.DEVNULL,
        )
        return out.decode().strip()
    except Exception:
        return "unknown"


def _env_int(name: str, default: int, *, minimum: int = 1, maximum: int = 100000) -> int:
    raw = (os.getenv(name) or "").strip()
    if not raw:
        value = int(default)
    else:
        try:
            value = int(raw)
        except Exception:
            value = int(default)
    if value < minimum:
        value = minimum
    if value > maximum:
        value = maximum
    return value


def _ensure_referral_schema_compatibility():
    """
    Keep runtime compatibility for SQLite/dev test databases that may not have
    the latest referral columns yet.
    """
    try:
        engine = db.engine
        insp = inspect(engine)
        tables = set(insp.get_table_names())
        if "users" not in tables:
            return
        cols = {str(c.get("name", "")).lower() for c in insp.get_columns("users")}
        with engine.begin() as conn:
            if "referral_code" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN referral_code VARCHAR(32)"))
            if "referred_by" not in cols:
                conn.execute(text("ALTER TABLE users ADD COLUMN referred_by INTEGER"))
        try:
            from app.models import Referral

            Referral.__table__.create(bind=engine, checkfirst=True)
        except Exception:
            pass
    except Exception:
        # Schema compatibility best-effort only; never block startup.
        pass


def _ensure_notifications_schema_compatibility():
    """
    Keep runtime compatibility for databases where notifications table predates
    current model columns.
    """
    try:
        engine = db.engine
        insp = inspect(engine)
        tables = set(insp.get_table_names())
        if "notifications" not in tables:
            return
        cols_before = {
            str(c.get("name", "")).lower() for c in insp.get_columns("notifications")
        }
        dialect = (getattr(engine.dialect, "name", "") or "").lower()
        dt_type = "TIMESTAMP" if "postgres" in dialect else "DATETIME"
        add_specs = {
            "channel": "channel VARCHAR(32)",
            "title": "title VARCHAR(160)",
            "message": "message TEXT",
            "status": "status VARCHAR(24)",
            "provider": "provider VARCHAR(64)",
            "provider_ref": "provider_ref VARCHAR(120)",
            "created_at": f"created_at {dt_type}",
            "sent_at": f"sent_at {dt_type}",
            "meta": "meta TEXT",
        }
        with engine.begin() as conn:
            for name, ddl in add_specs.items():
                if name not in cols_before:
                    conn.execute(text(f"ALTER TABLE notifications ADD COLUMN {ddl}"))
            if "body" in cols_before:
                conn.execute(
                    text(
                        "UPDATE notifications SET message = COALESCE(body, '') "
                        "WHERE message IS NULL OR message = ''"
                    )
                )
            conn.execute(
                text("UPDATE notifications SET channel = 'in_app' WHERE channel IS NULL OR channel = ''")
            )
            conn.execute(
                text("UPDATE notifications SET status = 'queued' WHERE status IS NULL OR status = ''")
            )
            conn.execute(
                text("UPDATE notifications SET message = '' WHERE message IS NULL")
            )
            conn.execute(
                text("UPDATE notifications SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL")
            )
    except Exception:
        # Never block startup on compatibility patch-up.
        pass


def _ensure_listings_schema_compatibility():
    """
    Keep runtime compatibility for databases that predate listing metadata
    columns used by vehicles, power/energy, and real estate verticals.
    """
    try:
        engine = db.engine
        insp = inspect(engine)
        tables = set(insp.get_table_names())
        if "listings" not in tables:
            return
        dialect = (getattr(engine.dialect, "name", "") or "").lower()
        dt_type = "TIMESTAMP" if "postgres" in dialect else "DATETIME"
        cols_before = {str(c.get("name", "")).lower() for c in insp.get_columns("listings")}
        add_specs = {
            "listing_type": "listing_type VARCHAR(32) NOT NULL DEFAULT 'declutter'",
            "vehicle_metadata": "vehicle_metadata TEXT",
            "energy_metadata": "energy_metadata TEXT",
            "real_estate_metadata": "real_estate_metadata TEXT",
            "vehicle_make": "vehicle_make VARCHAR(80)",
            "vehicle_model": "vehicle_model VARCHAR(80)",
            "vehicle_year": "vehicle_year INTEGER",
            "battery_type": "battery_type VARCHAR(64)",
            "inverter_capacity": "inverter_capacity VARCHAR(64)",
            "lithium_only": "lithium_only BOOLEAN NOT NULL DEFAULT 0",
            "bundle_badge": "bundle_badge BOOLEAN NOT NULL DEFAULT 0",
            "property_type": "property_type VARCHAR(24)",
            "bedrooms": "bedrooms INTEGER",
            "bathrooms": "bathrooms INTEGER",
            "toilets": "toilets INTEGER",
            "parking_spaces": "parking_spaces INTEGER",
            "furnished": "furnished BOOLEAN",
            "serviced": "serviced BOOLEAN",
            "land_size": "land_size DOUBLE PRECISION",
            "title_document_type": "title_document_type VARCHAR(64)",
            "delivery_available": "delivery_available BOOLEAN",
            "inspection_required": "inspection_required BOOLEAN",
            "location_verified": "location_verified BOOLEAN NOT NULL DEFAULT 0",
            "inspection_request_enabled": "inspection_request_enabled BOOLEAN NOT NULL DEFAULT 0",
            "financing_option": "financing_option BOOLEAN NOT NULL DEFAULT 0",
            "approval_status": "approval_status VARCHAR(24) NOT NULL DEFAULT 'approved'",
            "inspection_flagged": "inspection_flagged BOOLEAN NOT NULL DEFAULT 0",
            "customer_payout_profile_json": "customer_payout_profile_json TEXT",
            "customer_profile_updated_at": f"customer_profile_updated_at {dt_type}",
            "customer_profile_updated_by": "customer_profile_updated_by INTEGER",
        }
        with engine.begin() as conn:
            for name, ddl in add_specs.items():
                if name not in cols_before:
                    conn.execute(text(f"ALTER TABLE listings ADD COLUMN {ddl}"))
            conn.execute(
                text(
                    "UPDATE listings SET listing_type='declutter' "
                    "WHERE listing_type IS NULL OR listing_type=''"
                )
            )
            conn.execute(
                text(
                    "UPDATE listings SET approval_status='approved' "
                    "WHERE approval_status IS NULL OR approval_status=''"
                )
            )
            conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_listings_make_model_year "
                    "ON listings (vehicle_make, vehicle_model, vehicle_year)"
                )
            )
            conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_listings_energy_filter_triplet "
                    "ON listings (battery_type, inverter_capacity, lithium_only)"
                )
            )
            conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_listings_real_estate_core "
                    "ON listings (property_type, bedrooms, bathrooms, furnished, serviced)"
                )
            )
            conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_listings_land_filters "
                    "ON listings (land_size, title_document_type)"
                )
            )
            conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_listings_listing_type "
                    "ON listings (listing_type)"
                )
            )
            conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_listings_approval_status "
                    "ON listings (approval_status)"
                )
            )
    except Exception:
        # Never block startup on compatibility patch-up.
        pass


def _ensure_saved_searches_schema_compatibility():
    try:
        from app.models import SavedSearch

        SavedSearch.__table__.create(bind=db.engine, checkfirst=True)
    except Exception:
        pass


def create_app():
    app = Flask(__name__)
    init_sentry(app)

    env = (os.getenv("FLIPTRYBE_ENV", "dev") or "dev").strip().lower()

    # Production safety checks
    if env in ("prod", "production"):
        secret = (os.getenv("SECRET_KEY") or "").strip()
        if not secret or len(secret) < 16:
            raise RuntimeError("SECRET_KEY must be set and at least 16 chars in production")
        if not (os.getenv("DATABASE_URL") or "").strip() and not (os.getenv("SQLALCHEMY_DATABASE_URI") or "").strip():
            raise RuntimeError("DATABASE_URL (or SQLALCHEMY_DATABASE_URI) must be set in production")

    # Basic config
    app.config["SECRET_KEY"] = os.getenv("SECRET_KEY", "dev-secret")
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

    # Ensure instance dir exists for SQLite paths
    instance_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "instance"))
    os.makedirs(instance_dir, exist_ok=True)

    # Database config
    database_url = os.getenv("SQLALCHEMY_DATABASE_URI") or os.getenv("DATABASE_URL")
    if not database_url:
        if env in ("prod", "production"):
            raise RuntimeError("DATABASE_URL (or SQLALCHEMY_DATABASE_URI) must be set in production")
        database_url = "sqlite:///instance/fliptrybe.db"
    # Keep SQLite on a single canonical file for this backend to avoid
    # cross-project drift when sibling repos also have fliptrybe.db files.
    if database_url.startswith("sqlite://") and database_url != "sqlite:///:memory:":
        canonical_path = os.path.join(instance_dir, "fliptrybe.db")
        database_url = f"sqlite:///{canonical_path.replace(os.sep, '/')}"
    if "fliptrybe-logistics" in database_url.replace("\\", "/"):
        raise RuntimeError("Invalid DATABASE_URL: must not point to fliptrybe-logistics")
    app.config["SQLALCHEMY_DATABASE_URI"] = database_url
    engine_options = {
        "pool_pre_ping": True,
        "pool_reset_on_return": "rollback",
        "pool_recycle": _env_int("DB_POOL_RECYCLE_SECONDS", 1800, minimum=60, maximum=86400),
    }
    if not database_url.startswith("sqlite://"):
        engine_options.update(
            {
                "pool_size": _env_int("DB_POOL_SIZE", 10, minimum=1, maximum=200),
                "max_overflow": _env_int("DB_MAX_OVERFLOW", 20, minimum=0, maximum=500),
                "pool_timeout": _env_int("DB_POOL_TIMEOUT_SECONDS", 30, minimum=1, maximum=300),
            }
        )
        app.logger.info(
            "db_pooling_enabled pool_size=%s max_overflow=%s pool_timeout=%s pool_recycle=%s pgbouncer_recommended=true",
            int(engine_options.get("pool_size", 0) or 0),
            int(engine_options.get("max_overflow", 0) or 0),
            int(engine_options.get("pool_timeout", 0) or 0),
            int(engine_options.get("pool_recycle", 0) or 0),
        )
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = engine_options

    # CORS configuration
    cors_origins = (os.getenv("CORS_ORIGINS") or "").strip()
    if env in ("prod", "production"):
        origins = [o.strip() for o in cors_origins.split(",") if o.strip()]
    else:
        origins = ["*"] if not cors_origins else [o.strip() for o in cors_origins.split(",") if o.strip()]
    cors.init_app(app, resources={r"/api/*": {"origins": origins}})

    # Init extensions
    db.init_app(app)
    migrate.init_app(app, db)
    install_request_observers(app)
    with app.app_context():
        _ensure_referral_schema_compatibility()
        _ensure_notifications_schema_compatibility()
        _ensure_listings_schema_compatibility()
        _ensure_saved_searches_schema_compatibility()
        otel_env = (os.getenv("OTEL_ENABLED") or "").strip() == "1"
        otel_setting = False
        try:
            otel_setting = bool(getattr(get_settings(), "otel_enabled", False))
        except Exception:
            otel_setting = False
        init_otel(app, enabled=bool(otel_env or otel_setting))

    @app.errorhandler(HTTPException)
    def _api_http_exception(error: HTTPException):
        # Keep API failures JSON-only for predictable frontend handling.
        if not request.path.startswith("/api/"):
            return error
        payload = {
            "ok": False,
            "error": error.name,
            "message": error.description or error.name,
            "status": int(error.code or 500),
        }
        rid = (getattr(g, "request_id", "") or "").strip()
        if rid:
            payload["trace_id"] = rid
        return jsonify(payload), int(error.code or 500)

    @app.errorhandler(Exception)
    def _api_unhandled_exception(error: Exception):
        app.logger.exception("unhandled_exception path=%s", request.path)
        if not request.path.startswith("/api/"):
            return jsonify(
                {
                    "ok": False,
                    "error": "InternalServerError",
                    "message": "Internal server error",
                }
            ), 500
        payload = {
            "ok": False,
            "error": "InternalServerError",
            "message": "Internal server error",
            "status": 500,
        }
        rid = (getattr(g, "request_id", "") or "").strip()
        if rid:
            payload["trace_id"] = rid
        return jsonify(payload), 500

    # Register API routes
    app.register_blueprint(auth_bp)
    app.register_blueprint(ride_bp)
    app.register_blueprint(market_bp)
    app.register_blueprint(shortlets_bp)
    app.register_blueprint(wallets_bp)
    app.register_blueprint(commission_bp)
    app.register_blueprint(notifq_bp)
    app.register_blueprint(leader_bp)
    app.register_blueprint(analytics_bp)
    app.register_blueprint(payout_pdf_bp)
    app.register_blueprint(autopilot_bp)
    app.register_blueprint(payments_settings_bp)
    app.register_blueprint(merchant_bp)
    app.register_blueprint(merchants_bp)
    app.register_blueprint(webhooks_bp)
    app.register_blueprint(notifications_bp)
    app.register_blueprint(receipts_bp)
    app.register_blueprint(driver_profile_bp)
    app.register_blueprint(kpi_bp)
    app.register_blueprint(notify_bp)
    app.register_blueprint(admin_notify_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(leaderboards_bp)
    app.register_blueprint(dispatcher_bp)
    app.register_blueprint(support_bp)
    app.register_blueprint(support_chat_bp)
    app.register_blueprint(support_chat_admin_bp)
    app.register_blueprint(inspector_req_bp)
    app.register_blueprint(inspector_req_admin_bp)
    app.register_blueprint(kyc_bp)
    app.register_blueprint(orders_bp)
    app.register_blueprint(inspections_bp)
    app.register_blueprint(settings_bp)
    app.register_blueprint(preferences_bp)
    app.register_blueprint(drivers_list_bp)
    app.register_blueprint(merchant_follow_bp)
    app.register_blueprint(moneybox_bp)
    app.register_blueprint(moneybox_system_bp)
    app.register_blueprint(public_bp)
    app.register_blueprint(public_payments_bp)
    app.register_blueprint(admin_ops_bp)
    app.register_blueprint(flags_bp)
    app.register_blueprint(referral_bp)
    app.register_blueprint(user_analytics_bp)
    app.register_blueprint(pricing_bp)
    app.register_blueprint(omega_bp)

    # Health check
    @app.get("/api/health")
    def health():
        db_state = "ok"
        db_error = None
        try:
            with db.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
        except Exception as e:
            db_state = "fail"
            msg = str(e)
            if msg:
                db_error = (msg[:300] + "...") if len(msg) > 300 else msg
        payload = {
            "ok": True,
            "service": "fliptrybe-backend",
            "env": env,
            "db": db_state,
            "git_sha": _resolve_git_sha(),
            "alembic_head": _resolve_alembic_head(),
        }
        if db_error:
            payload["db_error"] = db_error
        return jsonify(payload)

    @app.get("/")
    def root():
        return jsonify({
            "ok": True,
            "service": "fliptrybe-backend",
            "env": env,
        })

    @app.get("/api/version")
    def version():
        return jsonify({
            "ok": True,
            "alembic_head": _resolve_alembic_head(),
            "git_sha": _resolve_git_sha(),
        })

    @app.get("/api/debug/client-echo")
    def debug_client_echo():
        if not _probes_enabled():
            return jsonify({"message": "Not found"}), 404
        return jsonify({
            "ok": True,
            "received_x_fliptrybe_client": request.headers.get("X-Fliptrybe-Client"),
            "received_user_agent": request.headers.get("User-Agent"),
            "request_path": request.path,
        })

    def _debug_user_from_request():
        header = request.headers.get("Authorization", "")
        token = get_bearer_token(header)
        if not token and header.lower().startswith("token "):
            token = header.replace("Token ", "", 1).strip()
        info = {
            "has_auth": bool(header),
            "token_ok": False,
            "sub": None,
            "user_id": None,
            "role": None,
        }
        if not token:
            return None, info
        payload = decode_token(token)
        if not payload:
            return None, info
        info["token_ok"] = True
        info["sub"] = payload.get("sub")
        try:
            uid = int(info["sub"])
        except Exception:
            return None, info
        info["user_id"] = uid
        try:
            user = db.session.get(User, uid)
        except Exception:
            try:
                db.session.rollback()
            except Exception:
                pass
            user = None
        if user:
            role = (getattr(user, "role", None) or "buyer").strip().lower()
            info["role"] = role
        return user, info

    def _is_admin_user(user: User | None) -> bool:
        if not user:
            return False
        role = (getattr(user, "role", None) or "").strip().lower()
        if role == "admin":
            return True
        if getattr(user, "is_admin", False):
            return True
        try:
            return int(user.id or 0) == 1
        except Exception:
            return False

    def _probes_enabled() -> bool:
        return (os.getenv("DEBUG_PROBES") or "").strip() == "1"

    @app.get("/api/debug/whoami")
    def debug_whoami():
        if not _probes_enabled():
            return jsonify({"message": "Not found"}), 404
        user, info = _debug_user_from_request()
        if not info.get("token_ok"):
            return jsonify({"ok": False, **info}), 401
        return jsonify({"ok": True, **info}), 200

    @app.get("/api/debug/routes")
    def debug_routes():
        if not _probes_enabled():
            return jsonify({"message": "Not found"}), 404
        user, info = _debug_user_from_request()
        if not info.get("token_ok"):
            return jsonify({"ok": False, "message": "Unauthorized"}), 401
        if not _is_admin_user(user):
            return jsonify({"ok": False, "message": "Forbidden"}), 403
        items = []
        for rule in app.url_map.iter_rules():
            methods = sorted(m for m in rule.methods if m in ("GET", "POST", "PUT", "PATCH", "DELETE"))
            items.append({
                "rule": rule.rule,
                "methods": methods,
            })
        return jsonify({"ok": True, "count": len(items), "items": items}), 200

    @app.before_request
    def _capture_auth_context():
        g.auth_user_id = None
        g.auth_role = None
        try:
            import sentry_sdk

            sentry_sdk.set_user(None)
        except Exception:
            pass
        header = request.headers.get("Authorization", "")
        token = get_bearer_token(header)
        if not token and header.lower().startswith("token "):
            token = header.replace("Token ", "", 1).strip()
        if not token:
            return
        payload = decode_token(token)
        if not payload:
            return
        sub = payload.get("sub")
        try:
            uid = int(sub)
        except Exception:
            return
        g.auth_user_id = uid
        try:
            user = db.session.get(User, uid)
            if user:
                g.auth_role = (getattr(user, "role", None) or "buyer").strip().lower()
                try:
                    import sentry_sdk

                    sentry_sdk.set_user(
                        {
                            "id": str(uid),
                            "email": (getattr(user, "email", None) or "").strip() or None,
                        }
                    )
                    sentry_sdk.set_tag("auth_role", g.auth_role or "buyer")
                except Exception:
                    pass
        except Exception:
            try:
                db.session.rollback()
            except Exception:
                pass

    def _rate_limited_response(retry_after_seconds: int):
        retry_after = int(max(1, retry_after_seconds or 1))
        payload = {
            "ok": False,
            "error": {
                "code": "RATE_LIMITED",
                "retry_after_seconds": retry_after,
            },
        }
        rid = (getattr(g, "request_id", "") or "").strip()
        if rid:
            payload["trace_id"] = rid
        resp = jsonify(payload)
        resp.status_code = 429
        resp.headers["Retry-After"] = str(retry_after)
        return resp

    @app.before_request
    def _global_rate_limit_guard():
        if bool(app.config.get("TESTING")):
            allow_in_tests = (os.getenv("RATE_LIMIT_IN_TESTS") or "").strip().lower() in ("1", "true", "yes", "on")
            if not allow_in_tests:
                return None
        if not rate_limit_enabled(True):
            return None
        method = (request.method or "GET").strip().upper()
        if method == "OPTIONS":
            return None
        path = (request.path or "").strip()
        if not path.startswith("/api/"):
            return None

        auth_paths = (
            "/api/auth",
            "/api/login",
            "/api/register",
            "/api/otp",
            "/api/password",
        )
        is_auth_path = any(path.startswith(prefix) for prefix in auth_paths)
        if is_auth_path:
            subject = build_rate_limit_subject(
                scope="ip",
                user_id=None,
                request_obj=request,
            )
            ok_minute, retry_minute = check_limit(
                f"tier:auth:minute:{subject}",
                limit=10,
                window_seconds=60,
            )
            if not ok_minute:
                return _rate_limited_response(retry_minute)
            ok_hour, retry_hour = check_limit(
                f"tier:auth:hour:{subject}",
                limit=30,
                window_seconds=3600,
            )
            if not ok_hour:
                return _rate_limited_response(retry_hour)
            return None

        user_id = getattr(g, "auth_user_id", None)
        scope = "user" if user_id is not None else "ip"
        subject = build_rate_limit_subject(
            scope=scope,
            user_id=int(user_id) if user_id is not None else None,
            request_obj=request,
        )
        if method == "GET":
            limit = 120
            window_seconds = 60
            tier = "browse"
        else:
            limit = 60
            window_seconds = 60
            tier = "write"
        key = f"tier:{tier}:{method}:{path}:{subject}"
        ok, retry_after = check_limit(
            key,
            limit=limit,
            window_seconds=window_seconds,
        )
        if not ok:
            return _rate_limited_response(retry_after)
        return None

    @app.before_request
    def _log_client_fingerprint():
        if request.path.startswith("/api/"):
            fp = request.headers.get("X-Fliptrybe-Client")
            if fp:
                app.logger.info("X-Fliptrybe-Client=%s path=%s", fp, request.path)

    @app.before_request
    def _reset_db_session():
        try:
            db.session.rollback()
        except Exception:
            pass

    @app.teardown_request
    def _cleanup_db_session(exc):
        try:
            if exc is not None:
                db.session.rollback()
        finally:
            db.session.remove()


    # -------------------------
    # Autopilot: run small tick on requests (throttled)
    # -------------------------
    try:
        from app.utils.autopilot import tick as _autopilot_tick_hook
        @app.before_request
        def _fliptrybe_autopilot_before_request():
            try:
                _autopilot_tick_hook()
            except Exception:
                try:
                    db.session.rollback()
                except Exception:
                    pass
    except Exception:
        pass

    app.register_blueprint(driver_avail_bp)

    app.register_blueprint(payments_bp)
    app.register_blueprint(payment_intents_bp)
    app.register_blueprint(admin_payments_bp)
    app.register_blueprint(admin_payment_intents_bp)
    app.register_blueprint(recipient_bp)
    app.register_blueprint(driver_offer_bp)
    app.register_blueprint(drivers_bp)

    app.register_blueprint(audit_bp)
    app.register_blueprint(inspector_bonds_admin_bp)
    app.register_blueprint(role_change_bp)

    app.register_blueprint(recon_bp)

    @app.cli.command("bootstrap-admin")
    def bootstrap_admin():
        env = (os.getenv("FLIPTRYBE_ENV") or os.getenv("FLASK_ENV") or "dev").strip().lower()
        allow = (os.getenv("ALLOW_ADMIN_BOOTSTRAP") or "").strip() == "1"
        if env not in ("dev", "development", "local", "test") and not allow:
            raise click.ClickException("Admin bootstrap disabled. Set ALLOW_ADMIN_BOOTSTRAP=1 or FLIPTRYBE_ENV=dev.")

        email = (os.getenv("ADMIN_EMAIL") or "").strip().lower()
        password = (os.getenv("ADMIN_PASSWORD") or "").strip()
        phone = (os.getenv("ADMIN_PHONE") or "").strip()
        if not email or not password:
            raise click.ClickException("ADMIN_EMAIL and ADMIN_PASSWORD must be set.")
        if not phone:
            raise click.ClickException("ADMIN_PHONE must be set to create admin.")

        u = User.query.filter_by(email=email).first()
        try:
            if u:
                u.set_password(password)
                u.role = "admin"
                if not getattr(u, "phone", None):
                    u.phone = phone
            else:
                u = User(name=email.split("@")[0], email=email, role="admin", phone=phone)
                u.set_password(password)
                db.session.add(u)
            db.session.commit()
            click.echo(f"admin_bootstrap_ok {u.email}")
        except Exception as e:
            db.session.rollback()
            msg = str(e).lower()
            if "phone" in msg and "unique" in msg:
                raise click.ClickException("Phone already in use, choose a unique ADMIN_PHONE.")
            if "unique" in msg and "email" in msg:
                raise click.ClickException("Admin user already exists.")
            raise click.ClickException("Failed to bootstrap admin.")

    @app.cli.command("admin-reset-password")
    @click.option("--email", "email", required=False, help="Admin email to reset")
    @click.option("--password", "password", required=False, help="New password")
    def admin_reset_password(email: str | None, password: str | None):
        env = (os.getenv("FLIPTRYBE_ENV") or os.getenv("FLASK_ENV") or "dev").strip().lower()
        allow = (os.getenv("ALLOW_ADMIN_BOOTSTRAP") or "").strip() == "1"
        if env not in ("dev", "development", "local", "test") and not allow:
            raise click.ClickException("Admin reset disabled. Set ALLOW_ADMIN_BOOTSTRAP=1 or FLIPTRYBE_ENV=dev.")

        email = (email or os.getenv("ADMIN_EMAIL") or "").strip().lower()
        password = (password or os.getenv("ADMIN_PASSWORD") or "").strip()
        if not email or not password:
            raise click.ClickException("Provide --email/--password or set ADMIN_EMAIL and ADMIN_PASSWORD.")

        u = User.query.filter_by(email=email).first()
        if not u:
            raise click.ClickException("Admin user not found.")
        if (getattr(u, "role", "") or "").lower() != "admin":
            raise click.ClickException("Target user is not admin.")

        u.set_password(password)
        db.session.commit()
        click.echo(f"admin_password_reset_ok {u.email}")

    return app
