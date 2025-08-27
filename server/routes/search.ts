import express from 'express';
import { embed } from '../lib/rag';
import { collectionName, search as qdrantSearch } from '../lib/qdrant';
import { listJobs } from '../lib/db';

const router = express.Router();

// POST /api/search { query, jobId?, limit=8 }
router.post('/search', async (req, res) => {
  const { query, jobId, limit } = req.body || {};
  if (typeof query !== 'string' || !query.trim()) {
    return res.status(400).json({ error: { code: 'VALIDATION_ERROR', message: 'query is required' } });
  }

  // Determine target job
  let targetJobId: string | undefined = typeof jobId === 'string' && jobId ? jobId : undefined;
  if (!targetJobId) {
    const jobs = listJobs();
    if (!jobs.length) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'No jobs available for search' } });
    }
    targetJobId = jobs[0].id;
  }

  try {
    const vector = await embed(query);
    const cname = collectionName(targetJobId);
    const results = await qdrantSearch(cname, vector, typeof limit === 'number' ? limit : 8);
    const hits = results.map((r: any) => ({
      score: r.score ?? r?.result?.score ?? 0,
      name: r.payload?.name ?? r.payload?.fileName ?? '',
      url: r.payload?.url ?? '',
      text_snippet: (r.payload?.text || '').slice(0, 300)
    }));
    return res.json({ hits });
  } catch (e: any) {
    return res.status(500).json({ error: { code: 'SEARCH_FAILED', message: e?.message || 'Search failed' } });
  }
});

export default router;