from flask_wtf import FlaskForm
from wtforms import PasswordField, StringField, SubmitField, TextAreaField
from wtforms.validators import DataRequired, Email, Length


class RegisterForm(FlaskForm):
    email = StringField("Email", validators=[DataRequired(), Email(), Length(max=255)])
    password = PasswordField(
        "Password",
        validators=[DataRequired(), Length(min=10, message="Use at least 10 characters.")],
    )
    submit = SubmitField("Create account")


class LoginForm(FlaskForm):
    email = StringField("Email", validators=[DataRequired(), Email(), Length(max=255)])
    password = PasswordField("Password", validators=[DataRequired()])
    submit = SubmitField("Log in")


class NoteForm(FlaskForm):
    title = StringField("Title", validators=[DataRequired(), Length(max=200)])
    body = TextAreaField("Body", validators=[Length(max=10_000)])
    submit = SubmitField("Save")
