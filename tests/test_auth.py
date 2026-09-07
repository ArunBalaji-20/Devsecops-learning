from tests.conftest import login, register


def test_register_then_redirected_to_notes(client):
    resp = register(client)
    assert resp.status_code == 200
    assert b"My notes" in resp.data


def test_duplicate_registration_is_rejected(client):
    register(client)
    client.get("/auth/logout")
    resp = register(client)
    assert b"Could not create account" in resp.data


def test_login_with_wrong_password_fails(client):
    register(client)
    client.get("/auth/logout")
    resp = login(client, password="totally-wrong-password")
    assert b"Invalid email or password" in resp.data


def test_login_success(client):
    register(client)
    client.get("/auth/logout")
    resp = login(client)
    assert b"My notes" in resp.data


def test_notes_requires_login(client):
    resp = client.get("/notes/", follow_redirects=True)
    # Anonymous users get bounced to the login page, not the notes list.
    assert b"Log in" in resp.data
