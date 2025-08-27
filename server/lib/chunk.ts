/**
 * Chunking utilities for RAG
 * - normalize: collapse whitespace but preserve markdown heading lines
 * - chunkBySentences: build ~800-token chunks with ~120-token overlap
 * Returns chunk objects: { id, ord, text, meta:{ name, url } }
 */

export type RagChunk = {
  id: string;
  ord: number;
  text: string;
  meta: { name: string; url: string };
};

export function normalize(input: string): string {
  if (!input) return '';
  // Preserve lines that start with heading markers, collapse other whitespace
  const lines = input.split(/\r?\n/);
  const out: string[] = [];
  for (const line of lines) {
    if (/^\s*#{1,6}\s+/.test(line)) {
      out.push(line.trimEnd());
    } else {
      // collapse internal whitespace
      const collapsed = line.replace(/\s+/g, ' ').trim();
      if (collapsed) out.push(collapsed);
    }
  }
  // Ensure single newline between blocks
  return out.join('\n');
}

function estimateTokens(text: string): number {
  // Rough heuristic: ~4 chars per token
  return Math.ceil(text.length / 4);
}

function splitIntoParagraphs(text: string): string[] {
  // First pass: split by headings (keep them as separate paragraphs)
  const lines = text.split(/\r?\n/);
  const paras: string[] = [];
  let buf: string[] = [];
  const flush = () => {
    if (buf.length) {
      paras.push(buf.join(' ').trim());
      buf = [];
    }
  };
  for (const line of lines) {
    if (/^\s*#{1,6}\s+/.test(line)) {
      flush();
      paras.push(line.trim());
    } else if (!line.trim()) {
      flush();
    } else {
      buf.push(line.trim());
    }
  }
  flush();
  return paras.filter(Boolean);
}

function splitIntoSentences(text: string): string[] {
  // Naive sentence splitter that keeps some punctuation context
  const parts = text
    .replace(/\r/g, '')
    .split(/(?<=[\.!\?])\s+|\n+/)
    .map(s => s.trim())
    .filter(Boolean);
  return parts;
}

export function chunkTextToRag(
  rawText: string,
  name: string,
  url: string,
  targetTokens: number = 800,
  overlapTokens: number = 120
): RagChunk[] {
  const text = normalize(rawText);
  if (!text) return [];
  const paragraphs = splitIntoParagraphs(text);
  // Expand to sentence list while keeping headings as standalone sentences
  const sentences: string[] = [];
  for (const p of paragraphs) {
    if (/^\s*#{1,6}\s+/.test(p)) {
      sentences.push(p);
    } else {
      const ss = splitIntoSentences(p);
      sentences.push(...ss);
    }
  }

  const chunks: RagChunk[] = [];
  let i = 0;
  let ord = 0;
  while (i < sentences.length) {
    let tokens = 0;
    const buf: string[] = [];
    let j = i;
    for (; j < sentences.length; j++) {
      const s = sentences[j];
      const t = estimateTokens(s);
      if (buf.length > 0 && tokens + t > targetTokens) break;
      buf.push(s);
      tokens += t;
    }
    const textChunk = buf.join(' ').trim();
    if (textChunk) {
      chunks.push({
        id: `${name}:${ord}`,
        ord,
        text: textChunk,
        meta: { name, url }
      });
      ord++;
    }
    if (j >= sentences.length) break;
    // Overlap: step back so next chunk includes ~overlapTokens worth of sentences
    let backTokens = 0;
    let k = j - 1;
    while (k >= 0 && backTokens < overlapTokens) {
      backTokens += estimateTokens(sentences[k]);
      k--;
    }
    i = Math.max(0, j - Math.max(1, (j - 1) - k));
  }
  return chunks;
}