import express from 'express';
import { randomUUID } from 'crypto';
import { CreateJobRequest, Job } from '../types';
import {
  appendLog,
  createJob,
  getFiles,
  getJob,
  getLogs,
  listJobs,
  saveFiles,
  updateJob,
} from '../lib/db';
import { enqueue } from '../lib/queue';
import { scrape } from '../lib/scraper';
import { buildRag, listExportFiles } from '../lib/rag';
import path from 'path';
import { existsSync } from 'fs';
import { zip } from 'zip-a-folder';

const router = express.Router();

// POST /api/jobs
router.post('/jobs', async (req, res) => {
  const parsed = CreateJobRequest.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid request body',
        details: parsed.error.flatten(),
      },
    });
  }

  const { urls, type, depth, maxPages, format } = parsed.data;
  const id = randomUUID();
  const createdAt = new Date().toISOString();

  try {
    createJob({ id, type, format, createdAt });
    appendLog(id, 'info', `Job created: ${type}, ${format}`);

    // Enqueue background work
    enqueue(id, async () => {
      try {
        updateJob(id, { status: 'running', progress: 0 });
        appendLog(id, 'info', 'Job started');
        appendLog(id, 'info', 'Starting scrape…');

        // Scrape via unified pipeline (persists files and writes raw copies)
        const files = await scrape(
          { id, type, status: 'running', createdAt, format, urls, depth, maxPages } as any as Job,
          (level, message) => appendLog(id, level, message),
          (p) => {
            const scaled = Math.max(0, Math.min(70, Math.round(p)));
            updateJob(id, { progress: scaled });
          }
        );
        appendLog(id, 'info', `Collected ${files.length} files`);
        updateJob(id, { progress: 70 });

        // Build RAG artifacts (stubbed)
        appendLog(id, 'info', 'Building RAG…');
        const job: Job = {
          id,
          type,
          status: 'running',
          createdAt,
          format,
          progress: 70,
          files,
        };
        await buildRag(
          job,
          files,
          (level, message) => appendLog(id, level, message),
          (p) => {
            const clamped = Math.max(70, Math.min(99, Math.round(p)));
            updateJob(id, { progress: clamped });
          }
        );
        appendLog(id, 'info', 'RAG build completed');

        // Finalize
        updateJob(id, { status: 'completed', progress: 100 });
        appendLog(id, 'info', 'Job completed');
      } catch (err: any) {
        appendLog(id, 'error', err?.message ?? 'Unknown error');
        updateJob(id, { status: 'failed', error: err?.message ?? 'Unknown error' });
      }
    });

    return res.status(201).json({ jobId: id });
  } catch (err: any) {
    appendLog(id, 'error', err?.message ?? 'Unknown error on create');
    updateJob(id, { status: 'failed', error: err?.message ?? 'Unknown error on create' });
    return res.status(500).json({
      error: { code: 'CREATE_FAILED', message: 'Failed to create job' },
    });
  }
});

// GET /api/jobs
router.get('/jobs', (req, res) => {
  const jobs = listJobs();
  res.json({ jobs });
});

// GET /api/jobs/:id/status
router.get('/jobs/:id/status', (req, res) => {
  const id = req.params.id;
  const job = getJob(id);
  if (!job) {
    return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Job not found' } });
  }
  const logs = getLogs(id).map((l: any) => l.message);
  res.json({
    status: job.status,
    progress: job.progress ?? 0,
    logs,
  });
});

// GET /api/jobs/:id/results
router.get('/jobs/:id/results', (req, res) => {
  const id = req.params.id;
  const job = getJob(id);
  if (!job) {
    return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Job not found' } });
  }
  // List export artifacts (JSONL and/or markdown exports)
  const exportsList = listExportFiles(id);
  const files = exportsList.map(f => ({
    name: f.name,
    url: `/api/jobs/${id}/download?file=${encodeURIComponent(f.name)}`,
    type: 'export'
  }));
  res.json({ files });
});

// GET /api/jobs/:id/download?format=zip&file=relativeName
router.get('/jobs/:id/download', async (req, res) => {
  const id = req.params.id;
  const job = getJob(id);
  if (!job) {
    return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Job not found' } });
  }
  const cacheRoot = path.join(process.cwd(), 'server', '.cache', 'jobs', id);
  const exportDir = path.join(cacheRoot, 'exports');
  if (!existsSync(exportDir)) {
    return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'No exports available' } });
  }

  const file = (req.query.file as string) || '';
  if (file) {
    // Stream a single export file safely
    const resolved = path.normalize(path.join(exportDir, file));
    if (!resolved.startsWith(exportDir)) {
      return res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Invalid file path' } });
    }
    if (!require('fs').existsSync(resolved)) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'File not found' } });
    }
    res.setHeader('Content-Disposition', `attachment; filename="${path.basename(resolved)}"`);
    return require('fs').createReadStream(resolved).pipe(res);
  }

  // Zip export directory on demand
  const zipPath = path.join(cacheRoot, 'exports.zip');
  try {
    await zip(exportDir, zipPath);
  } catch (e: any) {
    return res.status(500).json({ error: { code: 'ZIP_FAILED', message: e?.message || 'Zip failed' } });
  }
  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', `attachment; filename="job_${id}_exports.zip"`);
  require('fs').createReadStream(zipPath).pipe(res);
});

export default router;