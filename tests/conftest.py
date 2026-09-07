import pytest

from app import create_app
from app.extensions import db


@pytest.fixture()
def app():
    application = create_app("testing")
    with application.app_context():
        db.create_all()
        yield application
        db.session.remove()
        db.drop_all()


@pytest.fixture()
def client(app):
    return app.test_client()


def register(client, email="user@example.com", password="correct-horse-battery"):  # noqa: S107
    return client.post(
        "/auth/register",
        data={"email": email, "password": password},
        follow_redirects=True,
    )


def login(client, email="user@example.com", password="correct-horse-battery"):  # noqa: S107
    return client.post(
        "/auth/login",
        data={"email": email, "password": password},
        follow_redirects=True,
    )
