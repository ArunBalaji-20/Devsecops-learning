from flask import Blueprint, abort, flash, redirect, render_template, url_for
from flask_login import current_user, login_required

from app.extensions import db
from app.forms import NoteForm
from app.models import Note

notes_bp = Blueprint("notes", __name__, url_prefix="/notes")


def _get_owned_note_or_404(note_id: int) -> Note:
    """Fetch a note and enforce that it belongs to the current user.

    This is the app's access-control boundary: without the user_id
    check below, any logged-in user could read or edit another user's
    notes by guessing/incrementing the id in the URL (an IDOR — the
    kind of authorization bug SAST/DAST tools often miss and a manual
    pentest step is meant to catch).
    """
    note = db.session.get(Note, note_id)
    if note is None or note.user_id != current_user.id:
        abort(404)
    return note


@notes_bp.route("/")
@login_required
def list_notes():
    notes = (
        Note.query.filter_by(user_id=current_user.id)
        .order_by(Note.updated_at.desc())
        .all()
    )
    return render_template("notes/list.html", notes=notes)


@notes_bp.route("/new", methods=["GET", "POST"])
@login_required
def new_note():
    form = NoteForm()
    if form.validate_on_submit():
        note = Note(title=form.title.data, body=form.body.data or "", user_id=current_user.id)
        db.session.add(note)
        db.session.commit()
        flash("Note created.", "success")
        return redirect(url_for("notes.list_notes"))
    return render_template("notes/form.html", form=form, heading="New note")


@notes_bp.route("/<int:note_id>/edit", methods=["GET", "POST"])
@login_required
def edit_note(note_id: int):
    note = _get_owned_note_or_404(note_id)
    form = NoteForm(obj=note)
    if form.validate_on_submit():
        note.title = form.title.data
        note.body = form.body.data or ""
        db.session.commit()
        flash("Note updated.", "success")
        return redirect(url_for("notes.list_notes"))
    return render_template("notes/form.html", form=form, heading="Edit note")


@notes_bp.route("/<int:note_id>/delete", methods=["POST"])
@login_required
def delete_note(note_id: int):
    note = _get_owned_note_or_404(note_id)
    db.session.delete(note)
    db.session.commit()
    flash("Note deleted.", "info")
    return redirect(url_for("notes.list_notes"))
