import path from 'path';
import { promises as fs, existsSync, mkdirSync, statSync } from 'fs';
import * as nodeFs from 'fs';
import { load } from 'cheerio';
// ...
const $ = load(html);
import git from 'isomorphic-git';
import http from 'isomorphic-git/http/node';
import { globby } from 'globby';
import { fetch } from 'undici';
import { FileRec, Job } from '../types';
import { saveFiles } from './db';

type LogFn = (level: 'info' | 'error' | 'debug', message: string) => void;
type ReportProgressFn = (progress0to70: number) => void;

const CACHE_ROOT = path.join(process.cwd(), 'server', '.cache', 'jobs');

function ensureDir(dir: string) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

function sanitizeFileName(name: string): string {
  return name.replace(/[\\/:*?"<>|]/g, '_');
}

async function fetchWithRetry(url: string, timeoutMs = 15000, retries = 2): Promise<string | null> {
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ac = new AbortController();
    const id = setTimeout(() => ac.abort(), timeoutMs);
    try {
      const res = await fetch(url, { signal: ac.signal } as any);
      clearTimeout(id);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const text = await res.text();
      return text;
    } catch (e) {
      clearTimeout(id);
      if (attempt === retries) return null;
      await new Promise(r => setTimeout(r, 500 * (attempt + 1)));
    }
  }
  return null;
}

function extractReadable(html: string, baseUrl: string): { title: string; text: string } {
  const $ = cheerio.load(html);
  // Strip noisy elements
  const noisy = ['script', 'style', 'nav', 'footer', 'header', 'aside', 'noscript'];
  noisy.forEach(sel => $(sel).remove());
  // Prefer headings and paragraphs
  const parts: string[] = [];
  const title = ($('title').first().text() || '').trim();
  $('h1,h2,h3,h4,h5,h6,p,li,pre,code').each((_, el) => {
    const t = $(el).text().trim();
    if (t) parts.push(t);
  });
  const text = parts.join('\n\n');
  return { title, text };
}

function isSameOrigin(u: URL, origin: string): boolean {
  return u.origin === origin;
}

function normalizeUrl(href: string, base: string): URL | null {
  try {
    const url = new URL(href, base);
    if (['http:', 'https:'].includes(url.protocol)) return url;
    return null;
  } catch {
    return null;
  }
}

async function crawlDocs(seeds: string[], depth: number, maxPages: number, log: LogFn, report: ReportProgressFn): Promise<FileRec[]> {
  const visited = new Set<string>();
  const queue: Array<{ url: string; depth: number; origin: string }> = [];
  const files: FileRec[] = [];
  let processed = 0;

  // Initialize queue with seeds, track their origin
  for (const s of seeds) {
    try {
      const u = new URL(s);
      queue.push({ url: u.toString(), depth: 0, origin: u.origin });
    } catch {
      log('error', `Invalid URL seed: ${s}`);
    }
  }

  while (queue.length && processed < maxPages) {
    const { url, depth: d, origin } = queue.shift()!;
    if (visited.has(url)) continue;
    visited.add(url);

    log('debug', `Fetch ${url} (depth ${d})`);
    const html = await fetchWithRetry(url);
    if (!html) {
      log('error', `Failed to fetch ${url}`);
      continue;
    }

    const { title, text } = extractReadable(html, url);
    const content = [title, text].filter(Boolean).join('\n\n').trim();
    if (content) {
      const nameFromPath = sanitizeFileName(new URL(url).pathname.replace(/^\/+/, '') || 'index.html');
      const name = nameFromPath.endsWith('.html') ? nameFromPath : `${nameFromPath || 'index'}.html`;
      const rec: FileRec = {
        name,
        url,
        type: 'doc',
        text: content,
        sizeBytes: Buffer.byteLength(content, 'utf-8'),
      };
      files.push(rec);
      processed++;
      const progress = Math.min(70, Math.round((processed / Math.max(1, maxPages)) * 70));
      report(progress);
    }

    if (d < depth) {
      const $ = cheerio.load(html);
      $('a[href]').each((_, a) => {
        const href = $(a).attr('href') || '';
        if (!href) return;
        if (href.startsWith('#') || href.startsWith('mailto:') || href.startsWith('javascript:')) return;
        const u = normalizeUrl(href, url);
        if (!u) return;
        if (!isSameOrigin(u, origin)) return; // same-origin restriction
        const clean = u.toString().replace(/#.*$/, '');
        if (!visited.has(clean)) {
          queue.push({ url: clean, depth: d + 1, origin });
        }
      });
    }
  }

  return files;
}

function parseGitHubRepoUrl(repoUrl: string): { org: string; repo: string } | null {
  try {
    const u = new URL(repoUrl);
    if (u.hostname !== 'github.com') return null;
    const parts = u.pathname.split('/').filter(Boolean);
    if (parts.length < 2) return null;
    return { org: parts[0], repo: parts[1] };
  } catch {
    return null;
  }
}

async function scrapeRepo(repoUrl: string, repoDir: string, log: LogFn) {
  const parsed = parseGitHubRepoUrl(repoUrl);
  if (!parsed) throw new Error(`Unsupported repo URL: ${repoUrl}`);
  const { org, repo } = parsed;
  const url = `https://github.com/${org}/${repo}.git`;
  ensureDir(repoDir);
  log('info', `Cloning ${url} (shallow)`);
  await git.clone({
    fs: nodeFs as any,
    http,
    dir: repoDir,
    url,
    depth: 1,
    singleBranch: true
  });
}

async function collectRepoFiles(repoUrl: string, repoDir: string, log: LogFn): Promise<FileRec[]> {
  // Glob patterns for docs and code
  const docGlobs = ['**/*.md', '**/*.rst', '**/*.txt', 'docs/**/*'];
  const codeGlobs = ['**/*.ts', '**/*.tsx', '**/*.js', '**/*.py', '**/*.go', '**/*.rs'];
  const patterns = [...docGlobs, ...codeGlobs];
  const paths = await globby(patterns, { cwd: repoDir, gitignore: true, dot: false });
  log('info', `Globbing collected ${paths.length} candidate files`);

  const files: FileRec[] = [];
  for (const rel of paths) {
    const abs = path.join(repoDir, rel);
    try {
      const s = statSync(abs);
      if (!s.isFile()) continue;
      if (s.size > 200 * 1024) continue; // 200KB cap
      const text = await fs.readFile(abs, 'utf-8');
      const sizeBytes = Buffer.byteLength(text, 'utf-8');
      const rec: FileRec = {
        name: rel.replace(/\\/g, '/'),
        url: repoUrl.replace(/\/$/, '') + '/blob/HEAD/' + rel.replace(/\\/g, '/'),
        type: codeGlobs.some(g => rel.match(/\.(ts|tsx|js|py|go|rs)$/i)) ? 'code' : 'doc',
        text,
        sizeBytes
      };
      files.push(rec);
    } catch (e: any) {
      log('error', `Failed reading ${rel}: ${e.message || e}`);
    }
  }
  return files;
}

/**
 * Unified scrape entrypoint. Persists files and writes raw copies.
 * Calls reportProgress in 0..70 range as it collects.
 */
export async function scrape(
  job: Job,
  log: LogFn,
  reportProgress: ReportProgressFn
): Promise<FileRec[]> {
  const jobCache = path.join(CACHE_ROOT, job.id);
  const rawDir = path.join(jobCache, 'raw');
  const repoDir = path.join(jobCache, 'repo');
  ensureDir(jobCache);
  ensureDir(rawDir);

  let collected: FileRec[] = [];

  if (job.type === 'docs') {
    // Expect job has urls, depth, maxPages from request context; defaulting if absent
    // This function assumes route passes those in via a wrapper; here we just crawl seeds from logs if needed.
    log('info', 'Starting website crawl');
    // Fallbacks for depth/maxPages not present on Job type: use sane defaults
    const seeds = (job as any).urls ?? [];
    const depth = (job as any).depth ?? 3;
    const maxPages = (job as any).maxPages ?? 100;
    collected = await crawlDocs(seeds, depth, maxPages, log, reportProgress);
  } else if (job.type === 'repo') {
    const urls: string[] = (job as any).urls ?? [];
    const all: FileRec[] = [];
    for (const repoUrl of urls) {
      try {
        await scrapeRepo(repoUrl, repoDir, log);
        const files = await collectRepoFiles(repoUrl, repoDir, log);
        all.push(...files);
        // Progress approximation by file count
        const p = Math.min(70, Math.round((all.length / Math.max(1, files.length)) * 70));
        reportProgress(p);
      } catch (e: any) {
        log('error', `Repo scrape failed for ${repoUrl}: ${e.message || e}`);
      }
    }
    collected = all;
  } else {
    log('error', `Unknown job type: ${(job as any).type}`);
  }

  // Write raw copies
  for (let i = 0; i < collected.length; i++) {
    const f = collected[i];
    const nnn = String(i + 1).padStart(4, '0');
    const base = sanitizeFileName(f.name);
    const out = path.join(rawDir, `${nnn}_${base}`);
    try {
      await fs.writeFile(out, f.text ?? '', 'utf-8');
    } catch (e: any) {
      log('error', `Failed writing raw copy ${out}: ${e.message || e}`);
    }
  }

  // Persist to DB with ord
  const records = collected.map((f, idx) => ({
    ord: idx,
    name: f.name,
    url: f.url,
    type: f.type,
    sizeBytes: f.sizeBytes,
    text: f.text
  }));
  try {
    saveFiles(job.id, records);
    log('info', `Persisted ${records.length} files`);
  } catch (e: any) {
    log('error', `Failed persisting files: ${e.message || e}`);
  }

  return collected;
}