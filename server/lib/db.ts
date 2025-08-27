import Database from 'better-sqlite3';
import { mkdirSync } from 'fs';
import path from 'path';

// Ensure data directory exists
const dataDir = path.join(process.cwd(), 'server', 'data');
mkdirSync(dataDir, { recursive: true });

// Initialize database connection
const db = new Database(path.join(dataDir, 'app.db'));

// Database migrations
db.exec(`
CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  progress INTEGER DEFAULT 0,
  type TEXT NOT NULL,
  format TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  error TEXT
);

CREATE TABLE IF NOT EXISTS logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  jobId TEXT NOT NULL,
  ts TEXT NOT NULL,
  level TEXT NOT NULL,
  message TEXT NOT NULL,
  FOREIGN KEY (jobId) REFERENCES jobs(id)
);

CREATE TABLE IF NOT EXISTS files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  jobId TEXT NOT NULL,
  ord INTEGER NOT NULL,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  type TEXT NOT NULL,
  sizeBytes INTEGER,
  text TEXT,
  FOREIGN KEY (jobId) REFERENCES jobs(id)
);
`);

// Helper functions
export const createJob = (job: {
  id: string;
  type: string;
  format: string;
  createdAt: string;
}) => {
  return db.prepare(`
    INSERT INTO jobs (id, status, type, format, createdAt)
    VALUES (?, 'queued', ?, ?, ?)
  `).run(job.id, job.type, job.format, job.createdAt);
};

export const updateJob = (id: string, updates: {
  status?: string;
  progress?: number;
  error?: string;
}) => {
  const setClauses = [];
  const params = [];
  
  if (updates.status) {
    setClauses.push('status = ?');
    params.push(updates.status);
  }
  if (updates.progress !== undefined) {
    setClauses.push('progress = ?');
    params.push(updates.progress);
  }
  if (updates.error !== undefined) {
    setClauses.push('error = ?');
    params.push(updates.error);
  }
  
  params.push(id);
  return db.prepare(`
    UPDATE jobs SET ${setClauses.join(', ')} WHERE id = ?
  `).run(...params);
};

export const appendLog = (jobId: string, level: string, message: string) => {
  return db.prepare(`
    INSERT INTO logs (jobId, ts, level, message)
    VALUES (?, datetime('now'), ?, ?)
  `).run(jobId, level, message);
};

export const saveFiles = (jobId: string, files: Array<{
  ord: number;
  name: string;
  url: string;
  type: string;
  sizeBytes?: number;
  text?: string;
}>) => {
  const insert = db.prepare(`
    INSERT INTO files (jobId, ord, name, url, type, sizeBytes, text)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  
  const transaction = db.transaction((files) => {
    for (const file of files) {
      insert.run(
        jobId,
        file.ord,
        file.name,
        file.url,
        file.type,
        file.sizeBytes,
        file.text
      );
    }
  });
  
  return transaction(files);
};

export const listJobs = () => {
  return db.prepare(`
    SELECT id, status, type, format, createdAt
    FROM jobs
    ORDER BY createdAt DESC
    LIMIT 50
  `).all();
};

export const getJob = (id: string) => {
  return db.prepare(`
    SELECT * FROM jobs WHERE id = ?
  `).get(id);
};

export const getFiles = (jobId: string) => {
  return db.prepare(`
    SELECT * FROM files WHERE jobId = ? ORDER BY ord
  `).all(jobId);
};

export const getLogs = (jobId: string) => {
  return db.prepare(`
    SELECT * FROM logs WHERE jobId = ? ORDER BY ts
  `).all(jobId);
};

export default db;