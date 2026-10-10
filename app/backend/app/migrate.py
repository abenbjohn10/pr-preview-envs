"""Run migrations to head, then seed. Invoked as `python -m app.migrate`."""

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import select

from app.db import SessionLocal
from app.models import Note

ROOT = Path(__file__).resolve().parent.parent

SEED_NOTES = [
    ("Welcome to your preview environment", "This stack was created for this pull request."),
    ("Isolated by design", "Own namespace, own Postgres, own URL."),
    ("Torn down on close", "Closing the PR deletes the namespace and everything in it."),
]


def upgrade() -> None:
    cfg = Config(str(ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(ROOT / "alembic"))
    command.upgrade(cfg, "head")


def seed() -> None:
    with SessionLocal() as session:
        if session.scalars(select(Note.id).limit(1)).first() is not None:
            return
        session.add_all(Note(title=t, body=b) for t, b in SEED_NOTES)
        session.commit()


def main() -> None:
    upgrade()
    seed()


if __name__ == "__main__":
    main()
