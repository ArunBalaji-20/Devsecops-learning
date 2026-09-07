import os

from flask import Flask

from app.extensions import csrf, db, login_manager
from config import CONFIG_BY_NAME


def create_app(config_name: str | None = None) -> Flask:
    """Application factory. config_name selects one of the classes in
    config.CONFIG_BY_NAME (defaults to $FLASK_ENV, then 'production')."""

    config_name = config_name or os.environ.get("FLASK_ENV", "production")
    config_cls = CONFIG_BY_NAME.get(config_name, CONFIG_BY_NAME["production"])

    app = Flask(__name__)
    app.config.from_object(config_cls)

    missing = [name for name in config_cls.REQUIRED if not app.config.get(name)]
    if missing:
        raise RuntimeError(
            "Missing required configuration: "
            + ", ".join(missing)
            + ". Set these as environment variables (see .env.example) "
            "before starting the app."
        )

    db.init_app(app)
    login_manager.init_app(app)
    csrf.init_app(app)

    from app.models import User

    @login_manager.user_loader
    def load_user(user_id: str):
        return db.session.get(User, int(user_id))

    from app.routes.auth import auth_bp
    from app.routes.notes import notes_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(notes_bp)

    @app.get("/healthz")
    def healthz():
        # Used by the ECS/ALB health check (terraform/ecs.tf, terraform/alb.tf)
        # and by the DAST workflow to confirm the app is up before scanning.
        return {"status": "ok"}, 200

    _register_security_headers(app)

    return app


def _register_security_headers(app: Flask) -> None:
    """A handful of baseline security headers. These are exactly the kind
    of thing a DAST scan (see .github/workflows/dast.yml) will flag as
    missing if you remove them — try commenting one out and re-running
    the ZAP baseline scan to see the finding appear."""

    @app.after_request
    def set_headers(response):
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "same-origin")
        response.headers.setdefault(
            "Content-Security-Policy", "default-src 'self'; style-src 'self'"
        )
        return response
