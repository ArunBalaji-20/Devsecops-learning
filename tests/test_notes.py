from app.extensions import db
from app.models import Note, User
from tests.conftest import register


def test_create_and_list_note(client):
    register(client)
    resp = client.post(
        "/notes/new",
        data={"title": "First note", "body": "hello world"},
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"First note" in resp.data
    assert b"hello world" in resp.data


def test_edit_note(client, app):
    register(client)
    client.post("/notes/new", data={"title": "Original", "body": "v1"})
    with app.app_context():
        note = Note.query.filter_by(title="Original").first()
        note_id = note.id

    resp = client.post(
        f"/notes/{note_id}/edit",
        data={"title": "Updated", "body": "v2"},
        follow_redirects=True,
    )
    assert b"Updated" in resp.data
    assert b"Original" not in resp.data


def test_delete_note(client, app):
    register(client)
    client.post("/notes/new", data={"title": "Temp", "body": "gone soon"})
    with app.app_context():
        note = Note.query.filter_by(title="Temp").first()
        note_id = note.id

    resp = client.post(f"/notes/{note_id}/delete", follow_redirects=True)
    assert b"Temp" not in resp.data


def test_cannot_access_another_users_note(client, app):
    # user A creates a note
    register(client, email="a@example.com")
    client.post("/notes/new", data={"title": "A's private note", "body": "secret"})
    with app.app_context():
        note = Note.query.filter_by(title="A's private note").first()
        note_id = note.id
    client.get("/auth/logout")

    # user B logs in and tries to open it directly by id
    register(client, email="b@example.com")
    resp = client.get(f"/notes/{note_id}/edit")
    assert resp.status_code == 404


def test_note_body_is_html_escaped(client):
    # Confirms Jinja2 autoescaping is doing its job — this is the app's
    # only real XSS defense for user-supplied note content.
    register(client)
    payload = "<script>alert(1)</script>"
    resp = client.post(
        "/notes/new",
        data={"title": "xss-check", "body": payload},
        follow_redirects=True,
    )
    assert b"<script>alert(1)</script>" not in resp.data
    assert b"&lt;script&gt;" in resp.data


def test_password_is_never_stored_in_plaintext(app):
    with app.app_context():
        user = User(email="hash@example.com")
        user.set_password("correct-horse-battery")
        db.session.add(user)
        db.session.commit()
        assert user.password_hash != "correct-horse-battery"
        assert user.check_password("correct-horse-battery")
        assert not user.check_password("wrong-password")
