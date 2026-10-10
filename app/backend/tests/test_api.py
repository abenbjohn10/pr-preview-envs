def test_health(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok", "db": "ok"}


def test_info(client):
    assert client.get("/api/info").json() == {"pr": "42", "sha": "abc1234"}


def test_create_and_list_notes(client):
    assert client.get("/api/notes").json() == []
    r = client.post("/api/notes", json={"title": "first", "body": "hello"})
    assert r.status_code == 201
    created = r.json()
    assert created["title"] == "first" and created["id"]

    client.post("/api/notes", json={"title": "second"})
    titles = [n["title"] for n in client.get("/api/notes").json()]
    assert titles == ["second", "first"]


def test_create_rejects_blank_title(client):
    assert client.post("/api/notes", json={"title": ""}).status_code == 422


def test_delete_note(client):
    note_id = client.post("/api/notes", json={"title": "temp"}).json()["id"]
    assert client.delete(f"/api/notes/{note_id}").status_code == 204
    assert client.get("/api/notes").json() == []
    assert client.delete(f"/api/notes/{note_id}").status_code == 404
