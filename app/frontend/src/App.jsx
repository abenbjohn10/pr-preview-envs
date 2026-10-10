import { useCallback, useEffect, useState } from "react";
import { createNote, deleteNote, getInfo, listNotes } from "./api.js";

export default function App() {
  const [info, setInfo] = useState(null);
  const [notes, setNotes] = useState([]);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [error, setError] = useState(null);

  const refresh = useCallback(
    () => listNotes().then(setNotes).catch((e) => setError(e.message)),
    [],
  );

  useEffect(() => {
    getInfo().then(setInfo).catch(() => {});
    refresh();
  }, [refresh]);

  async function onSubmit(e) {
    e.preventDefault();
    if (!title.trim()) return;
    try {
      await createNote({ title: title.trim(), body: body.trim() });
      setTitle("");
      setBody("");
      setError(null);
      await refresh();
    } catch (err) {
      setError(err.message);
    }
  }

  async function onDelete(id) {
    try {
      await deleteNote(id);
      await refresh();
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <>
      <header className="banner">
        <span className="dot" />
        {info ? (
          <>
            Preview PR #{info.pr} <span className="sep">·</span>{" "}
            <code>{info.sha.slice(0, 7)}</code>
          </>
        ) : (
          "Preview environment"
        )}
      </header>

      <main>
        <h1>Notes</h1>
        <p className="lede">Each pull request gets its own copy of this app and database.</p>

        <form onSubmit={onSubmit} className="card form">
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Title"
            maxLength={200}
            aria-label="Title"
          />
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Details (optional)"
            rows={2}
            aria-label="Details"
          />
          <button type="submit" disabled={!title.trim()}>
            Add note
          </button>
        </form>

        {error && <p className="error">Something went wrong: {error}</p>}

        <ul className="notes">
          {notes.map((n) => (
            <li key={n.id} className="card note">
              <div>
                <h2>{n.title}</h2>
                {n.body && <p>{n.body}</p>}
                <time dateTime={n.created_at}>{new Date(n.created_at).toLocaleString()}</time>
              </div>
              <button className="ghost" onClick={() => onDelete(n.id)} aria-label={`Delete ${n.title}`}>
                Delete
              </button>
            </li>
          ))}
          {notes.length === 0 && <li className="empty">No notes yet.</li>}
        </ul>
      </main>
    </>
  );
}
