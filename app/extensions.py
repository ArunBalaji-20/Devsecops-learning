"""Flask extension instances, created here (unbound) to avoid circular
imports between app/__init__.py and app/models.py."""

from flask_login import LoginManager
from flask_sqlalchemy import SQLAlchemy
from flask_wtf import CSRFProtect

db = SQLAlchemy()
login_manager = LoginManager()
login_manager.login_view = "auth.login"
login_manager.login_message_category = "info"

# Registered app-wide (not just per-FlaskForm) so the plain POST forms
# like the "delete note" button are covered too, not only the ones
# built from a FlaskForm subclass. This also registers the csrf_token()
# Jinja global used in templates/notes/list.html.
csrf = CSRFProtect()
