from alembic import context

from app.db import Base, engine
from app.models import Note  # noqa: F401  (register metadata)

target_metadata = Base.metadata

with engine.connect() as connection:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()
