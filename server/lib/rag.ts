import path from 'path';
import { promises as fs, existsSync, mkdirSync, readdirSync } from 'fs';
import { fetch } from 'undici';
import { chunkTextToRag, RagChunk } from './chunk';
import { ensureCollection, upsertPoints, collectionName } from './qdrant';
import { FileRec, Job } from '../types';

const OLLAMA_URL = process.env.OLLAMA_URL || process.env.OLLAMA_HOST || 'http://localhost:11434';
const OLLAMA_EMBED_MODEL = process.env.OLLAMA_EMBED_MODEL || 'nomic-embed-text';
const RAG_DIM = Number(process.env.RAG_DIM || 384);
const RAG_COLLECTION_PREFIX = process.env.RAG_COLLECTION_PREFIX || 'job_';

type LogFn = (level: 'info' | 'error' | 'debug', message: string) => void;
type ReportProgressFn = (progress70to99: number) => void;

function ensureDir(p: string) {
  if (!existsSync(p)) mkdirSync(p, { recursive: true });
}

export async function embed(text: string): Promise<number[]> {
  const res = await fetch(`${OLLAMA_URL}/api/embeddings`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      model: OLLAMA_EMBED_MODEL,
      prompt: text
    })
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '<no-body>');
    throw new Error(`Ollama embed failed ${res.status}: ${body}`);
  }
  const json: any = await res.json();
  const vec: number[] = json?.embedding || json?.data?.[0]?.embedding;
  if (!Array.isArray(vec)) throw new Error('Invalid embedding response');
  return vec;
}

function batch<T>(arr: T[], size = 64): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

export async function buildRag(
  job: Job,
  files: FileRec[],
  log?: LogFn,
  reportProgress?: ReportProgressFn
): Promise<void> {
  log?.('info', `[RAG] Starting RAG for ${job.id}`);
  const cname = collectionName(job.id);
  await ensureCollection(cname, RAG_DIM, 'Cosine');

  const cacheRoot = path.join(process.cwd(), 'server', '.cache', 'jobs', job.id);
  const exportDir = path.join(cacheRoot, 'exports');
  const mdDir = path.join(exportDir, 'md');
  ensureDir(exportDir);
  if (job.format === 'markdown') ensureDir(mdDir);

  const jsonlPath = path.join(exportDir, 'rag_export.jsonl');
  const jsonlHandle = await fs.open(jsonlPath, 'w');

  try {
    let chunkCount = 0;
    let processed = 0;
    // Chunk each file
    for (const f of files) {
      const chunks: RagChunk[] = chunkTextToRag(f.text || '', f.name, f.url, 800, 120);
      // Prepare embeddings and points
      const points: { id: string; vector: number[]; payload: any }[] = [];
      for (const c of chunks) {
        const vector = await embed(c.text);
        points.push({
          id: `${job.id}:${c.ord}`,
          vector,
          payload: {
            jobId: job.id,
            url: c.meta.url,
            name: c.meta.name,
            ord: c.ord,
            text: c.text
          }
        });
        // Export JSONL line
        await jsonlHandle.writeFile(
          JSON.stringify({ id: `${job.id}:${c.ord}`, text: c.text, url: c.meta.url, name: c.meta.name, ord: c.ord }) + '\n',
          'utf-8'
        );
        chunkCount++;
        // Optional markdown export
        if (job.format === 'markdown') {
          const mdName = c.meta.name.replace(/[\\/:*?"<>|]/g, '_') + `.md`;
          const mdFile = path.join(mdDir, mdName);
          await fs.writeFile(mdFile, c.text, 'utf-8').catch(() => {});
        }
        // Progress 70..99
        processed++;
        const prog = 70 + Math.min(29, Math.floor((processed / Math.max(1, files.length)) * 29));
        reportProgress?.(prog);
      }
      // Upsert in batches
      for (const b of batch(points, 64)) {
        await upsertPoints(cname, b);
      }
      log?.('info', `[RAG] Processed file ${f.name}, chunks=${chunks.length}`);
    }
    log?.('info', `[RAG] Total chunks: ${chunkCount}`);
  } finally {
    await jsonlHandle.close();
  }
  log?.('info', `[RAG] Exported JSONL at ${jsonlPath}`);
}

/**
 * Helper to list downloadable export files for a job.
 * Returns absolute file paths and display names.
 */
export function listExportFiles(jobId: string): Array<{ name: string; path: string }> {
  const exportDir = path.join(process.cwd(), 'server', '.cache', 'jobs', jobId, 'exports');
  const out: Array<{ name: string; path: string }> = [];
  try {
    const entries = readdirSync(exportDir, { withFileTypes: true });
    for (const e of entries) {
      if (e.isFile()) out.push({ name: e.name, path: path.join(exportDir, e.name) });
    }
    const mdDir = path.join(exportDir, 'md');
    if (existsSync(mdDir)) {
      const mdEntries = readdirSync(mdDir, { withFileTypes: true });
      for (const e of mdEntries) {
        if (e.isFile()) out.push({ name: `md/${e.name}`, path: path.join(mdDir, e.name) });
      }
    }
  } catch {
    // ignore if exports missing
  }
  return out;
}