"""Production entrypoint (run by gunicorn — see Dockerfile CMD) and a
couple of flask CLI commands for local/dev database setup.

    flask --app wsgi init-db     # create tables
"""

import os

from app import create_app
from app.extensions import db

app = create_app()


@app.cli.command("init-db")
def init_db():
    """Create all tables. Fine for this learning project; a real
    production app would use Alembic/Flask-Migrate migrations instead
    of create_all() so schema changes are versioned."""
    with app.app_context():
        db.create_all()
    print("Database tables created.")


if __name__ == "__main__":
    # 0.0.0.0 is required so the app is reachable from outside its Docker
    # container/ECS task network namespace. gunicorn (see Dockerfile CMD)
    # is what actually serves this in every environment except a bare
    # `python wsgi.py` for local debugging, where this line runs instead.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)))  # noqa: S104
