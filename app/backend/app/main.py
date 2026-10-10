import os

from fastapi import Depends, FastAPI, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import check_db, get_session
from app.models import Note
from app.schemas import Info, NoteCreate, NoteOut

app = FastAPI(title="preview-notes", docs_url="/api/docs", openapi_url="/api/openapi.json")


@app.get("/api/health")
def health(response: Response, session: Session = Depends(get_session)):
    if check_db(session):
        return {"status": "ok", "db": "ok"}
    response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return {"status": "degraded", "db": "error"}


@app.get("/api/info", response_model=Info)
def info():
    return Info(pr=os.environ.get("PR_NUMBER", "local"), sha=os.environ.get("GIT_SHA", "dev"))


@app.get("/api/notes", response_model=list[NoteOut])
def list_notes(session: Session = Depends(get_session)):
    return session.scalars(select(Note).order_by(Note.id.desc())).all()


@app.post("/api/notes", response_model=NoteOut, status_code=status.HTTP_201_CREATED)
def create_note(payload: NoteCreate, session: Session = Depends(get_session)):
    note = Note(**payload.model_dump())
    session.add(note)
    session.commit()
    return note


@app.delete("/api/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: int, session: Session = Depends(get_session)):
    note = session.get(Note, note_id)
    if note is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "note not found")
    session.delete(note)
    session.commit()
