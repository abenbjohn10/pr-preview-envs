async function request(path, options) {
  const res = await fetch(`/api${path}`, options);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.status === 204 ? null : res.json();
}

export const getInfo = () => request("/info");
export const listNotes = () => request("/notes");
export const createNote = (note) =>
  request("/notes", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(note),
  });
export const deleteNote = (id) => request(`/notes/${id}`, { method: "DELETE" });
