import os
import subprocess
import click
from flask import Flask, jsonify, request
from sqlalchemy import text

from app.extensions import db, migrate, cors
from app.models import User
from app.segments.segment_09_users_auth_routes import auth_bp
from app.segments.segment_20_rides_routes import ride_bp
from app.segments.segment_payments import payments_bp
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
from app.segments.segment_autopilot import autopilot_bp
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
from app.segments.segment_demo import demo_bp
from app.segments.segment_orders_api import orders_bp
from app.segments.segment_inspections_api import inspections_bp
from app.segments.segment_settings import settings_bp
from app.segments.segment_kyc import kyc_bp
from app.segments.segment_drivers_list import drivers_list_bp
from app.segments.segment_merchant_follow import merchant_follow_bp
from app.segments.segment_inspector_bonds_admin import inspector_bonds_admin_bp
from app.segments.segment_role_change import role_change_bp
from app.segments.segment_moneybox import moneybox_bp, moneybox_system_bp
from app.segments.segment_public_feed import public_bp


def create_app():
    app = Flask(__name__)

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
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_pre_ping": True,
        "pool_reset_on_return": "rollback",
        "pool_recycle": 300,
    }

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
    app.register_blueprint(merchants_bp)
    app.register_blueprint(webhooks_bp)
    app.register_blueprint(notifications_bp)
    app.register_blueprint(receipts_bp)
    app.register_blueprint(driver_profile_bp)
    app.register_blueprint(kpi_bp)
    app.register_blueprint(notify_bp)
    app.register_blueprint(admin_notify_bp)
    app.register_blueprint(leaderboards_bp)
    app.register_blueprint(dispatcher_bp)
    app.register_blueprint(support_bp)
    app.register_blueprint(support_chat_bp)
    app.register_blueprint(support_chat_admin_bp)
    app.register_blueprint(kyc_bp)
    app.register_blueprint(orders_bp)
    app.register_blueprint(inspections_bp)
    app.register_blueprint(settings_bp)
    app.register_blueprint(drivers_list_bp)
    app.register_blueprint(merchant_follow_bp)
    app.register_blueprint(demo_bp)
    app.register_blueprint(moneybox_bp)
    app.register_blueprint(moneybox_system_bp)
    app.register_blueprint(public_bp)

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
        def _get_alembic_head() -> str:
            try:
                from alembic.config import Config
                from alembic.script import ScriptDirectory
                migrations_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "migrations"))
                cfg = Config(os.path.join(migrations_dir, "alembic.ini"))
                cfg.set_main_option("script_location", migrations_dir)
                script = ScriptDirectory.from_config(cfg)
                heads = script.get_heads()
                return heads[0] if heads else "unknown"
            except Exception:
                return "unknown"

        def _get_git_sha() -> str:
            try:
                repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
                out = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo_root, stderr=subprocess.DEVNULL)
                return out.decode().strip()
            except Exception:
                return "unknown"

        return jsonify({
            "ok": True,
            "alembic_head": _get_alembic_head(),
            "git_sha": _get_git_sha(),
        })

    @app.get("/api/debug/client-echo")
    def debug_client_echo():
        return jsonify({
            "ok": True,
            "received_x_fliptrybe_client": request.headers.get("X-Fliptrybe-Client"),
            "received_user_agent": request.headers.get("User-Agent"),
            "request_path": request.path,
        })

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
