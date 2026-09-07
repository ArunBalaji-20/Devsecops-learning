"""
Application configuration, loaded entirely from environment variables.

No secrets are ever hardcoded here. In local dev, values come from a
.env file (see .env.example) loaded by python-dotenv. In AWS, they are
injected as environment variables by ECS from AWS Secrets Manager /
SSM Parameter Store (see terraform/ecs.tf) — the container never sees
a secret that was written to disk in the image or in git.
"""

import os


def _normalize_db_url(url: str | None) -> str | None:
    if url and url.startswith("postgres://"):
        # SQLAlchemy 1.4+/2.x requires "postgresql://"; some providers
        # (Heroku-style) still hand out the old "postgres://" scheme.
        return url.replace("postgres://", "postgresql://", 1)
    return url


class Config:
    """Base config. Values are read lazily via os.environ so importing
    this module never crashes — required values are validated once in
    app/__init__.py::create_app(), which gives a clear startup error
    instead of a confusing import-time traceback."""

    SECRET_KEY = os.environ.get("FLASK_SECRET_KEY")
    SQLALCHEMY_DATABASE_URI = _normalize_db_url(os.environ.get("DATABASE_URL"))
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    # Only force secure cookies when actually served over HTTPS (e.g. behind
    # the ALB in AWS). Left off so plain-HTTP local dev still works.
    SESSION_COOKIE_SECURE = os.environ.get("FORCE_HTTPS_COOKIES", "false").lower() == "true"

    # Required, non-empty settings for this config. Subclasses that don't
    # need real secrets (e.g. TestingConfig) override this to [].
    REQUIRED = ["SECRET_KEY", "SQLALCHEMY_DATABASE_URI"]


class TestingConfig(Config):
    TESTING = True
    SECRET_KEY = "test-secret-key-not-for-production"  # noqa: S105 — test-only, never used outside pytest
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    WTF_CSRF_ENABLED = False
    REQUIRED: list[str] = []


CONFIG_BY_NAME = {
    "production": Config,
    "development": Config,
    "testing": TestingConfig,
}
