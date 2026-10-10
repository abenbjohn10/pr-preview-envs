from sqlalchemy import func, select

from app.db import SessionLocal
from app.migrate import main
from app.models import Note


def test_migrate_is_idempotent(client):
    from app.db import Base, engine

    Base.metadata.drop_all(engine)
    main()
    main()
    with SessionLocal() as s:
        assert s.scalar(select(func.count()).select_from(Note)) == 3
