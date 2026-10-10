import os

os.environ["DATABASE_URL"] = "sqlite"
os.environ["PR_NUMBER"] = "42"
os.environ["GIT_SHA"] = "abc1234"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.db import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture
def client():
    Base.metadata.create_all(engine)
    with TestClient(app) as c:
        yield c
    Base.metadata.drop_all(engine)
