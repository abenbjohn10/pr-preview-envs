import os

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool

DEFAULT_URL = "postgresql+psycopg://preview:preview@localhost:5432/preview"


class Base(DeclarativeBase):
    pass


def database_url() -> str:
    url = os.environ.get("DATABASE_URL", DEFAULT_URL)
    if url == "sqlite":
        return "sqlite+pysqlite://"
    # Accept plain postgresql:// URLs and route them to psycopg v3.
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg://", 1)
    return url


def make_engine(url: str | None = None) -> Engine:
    url = url or database_url()
    if url.startswith("sqlite"):
        # In-memory SQLite: one shared connection so all sessions see the same data.
        return create_engine(
            url,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
    return create_engine(url, pool_pre_ping=True)


engine = make_engine()
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def get_session():
    with SessionLocal() as session:
        yield session


def check_db(session: Session) -> bool:
    try:
        session.execute(text("SELECT 1"))
    except Exception:
        return False
    return True
