import { fetch } from 'undici';

const QDRANT_URL = process.env.QDRANT_URL || 'http://localhost:6333';
const QDRANT_API_KEY = process.env.QDRANT_API_KEY || '';
const RAG_COLLECTION_PREFIX = process.env.RAG_COLLECTION_PREFIX || 'job_';

function headers() {
  const h: Record<string, string> = { 'content-type': 'application/json' };
  if (QDRANT_API_KEY) h['api-key'] = QDRANT_API_KEY;
  return h;
}

export function collectionName(jobId: string): string {
  return `${RAG_COLLECTION_PREFIX}${jobId}`;
}

export async function ensureCollection(name: string, size: number, distance: 'Cosine' | 'Euclid' | 'Dot' = 'Cosine'): Promise<void> {
  const info = await fetch(`${QDRANT_URL}/collections/${encodeURIComponent(name)}`, {
    method: 'GET',
    headers: headers()
  });
  if (info.status === 200) return;
  if (info.status !== 404) {
    const body = await safeText(info);
    throw new Error(`Qdrant GET collection failed ${info.status}: ${body}`);
  }
  const res = await fetch(`${QDRANT_URL}/collections/${encodeURIComponent(name)}`, {
    method: 'PUT',
    headers: headers(),
    body: JSON.stringify({
      vectors: { size, distance }
    })
  });
  if (!res.ok) {
    const body = await safeText(res);
    throw new Error(`Qdrant ensureCollection failed ${res.status}: ${body}`);
  }
}

export async function upsertPoints(
  name: string,
  points: Array<{ id: string; vector: number[]; payload: any }>
): Promise<void> {
  const res = await fetch(`${QDRANT_URL}/collections/${encodeURIComponent(name)}/points`, {
    method: 'PUT',
    headers: headers(),
    body: JSON.stringify({ points })
  });
  if (!res.ok) {
    const body = await safeText(res);
    throw new Error(`Qdrant upsertPoints failed ${res.status}: ${body}`);
  }
}

export async function search(
  name: string,
  vector: number[],
  limit: number = 8,
  score_threshold?: number
): Promise<any[]> {
  const res = await fetch(`${QDRANT_URL}/collections/${encodeURIComponent(name)}/points/search`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      vector,
      limit,
      ...(score_threshold ? { score_threshold } : {})
    })
  });
  if (!res.ok) {
    const body = await safeText(res);
    throw new Error(`Qdrant search failed ${res.status}: ${body}`);
  }
  const json = await res.json();
  return json?.result ?? [];
}

async function safeText(r: any): Promise<string> {
  try {
    return await r.text();
  } catch {
    return '<no-body>';
  }
}