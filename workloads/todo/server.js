const path = require("path");
const crypto = require("crypto");
const express = require("express");
const Database = require("better-sqlite3");

const PORT = Number(process.env.PORT || 3000);
const APP_ENV = process.env.APP_ENV || "local";
const APP_VERSION = process.env.APP_VERSION || "0.1.0";
const DB_PATH = process.env.DB_PATH || path.join(__dirname, "data", "todo.db");
const APP_BANNER = process.env.APP_BANNER || "";
const DEMO_API_KEY = process.env.DEMO_API_KEY || "";

const fs = require("fs");
fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });

const db = new Database(DB_PATH);
db.exec(`
  CREATE TABLE IF NOT EXISTS todos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    done INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

const listStmt = db.prepare("SELECT id, title, done, created_at FROM todos ORDER BY id DESC");
const insertStmt = db.prepare("INSERT INTO todos (title) VALUES (?)");
const getStmt = db.prepare("SELECT id, title, done, created_at FROM todos WHERE id = ?");
const updateStmt = db.prepare(
  "UPDATE todos SET title = COALESCE(?, title), done = COALESCE(?, done) WHERE id = ?"
);
const deleteStmt = db.prepare("DELETE FROM todos WHERE id = ?");

function apiKeyFingerprint(key) {
  if (!key) return null;
  return crypto.createHash("sha256").update(key).digest("hex").slice(0, 12);
}

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

app.get("/healthz", (_req, res) => {
  res.json({ status: "ok", env: APP_ENV });
});

app.get("/api/meta", (_req, res) => {
  res.json({
    env: APP_ENV,
    version: APP_VERSION,
    banner: APP_BANNER || null,
    vault: {
      loaded: Boolean(APP_BANNER && DEMO_API_KEY),
      apiKeyFingerprint: apiKeyFingerprint(DEMO_API_KEY),
    },
  });
});

app.get("/api/todos", (_req, res) => {
  const rows = listStmt.all().map((r) => ({ ...r, done: Boolean(r.done) }));
  res.json(rows);
});

app.post("/api/todos", (req, res) => {
  const title = String(req.body?.title || "").trim();
  if (!title) {
    return res.status(400).json({ error: "title is required" });
  }
  const info = insertStmt.run(title);
  const row = getStmt.get(info.lastInsertRowid);
  res.status(201).json({ ...row, done: Boolean(row.done) });
});

app.patch("/api/todos/:id", (req, res) => {
  const id = Number(req.params.id);
  const existing = getStmt.get(id);
  if (!existing) {
    return res.status(404).json({ error: "not found" });
  }
  const title = req.body?.title !== undefined ? String(req.body.title).trim() : null;
  const done = req.body?.done !== undefined ? (req.body.done ? 1 : 0) : null;
  if (title !== null && !title) {
    return res.status(400).json({ error: "title cannot be empty" });
  }
  updateStmt.run(title, done, id);
  const row = getStmt.get(id);
  res.json({ ...row, done: Boolean(row.done) });
});

app.delete("/api/todos/:id", (req, res) => {
  const id = Number(req.params.id);
  const info = deleteStmt.run(id);
  if (info.changes === 0) {
    return res.status(404).json({ error: "not found" });
  }
  res.status(204).end();
});

app.listen(PORT, () => {
  console.log(
    `todo listening on :${PORT} env=${APP_ENV} vault=${Boolean(APP_BANNER && DEMO_API_KEY)} db=${DB_PATH}`
  );
});
