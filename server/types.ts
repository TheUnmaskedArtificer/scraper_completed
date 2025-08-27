import { z } from 'zod';

// Request schemas
export const CreateJobRequest = z.object({
  urls: z.array(z.string().url()),
  type: z.enum(['docs', 'repo']),
  depth: z.number().int().min(1).max(10).default(3),
  maxPages: z.number().int().min(1).max(2000).default(100),
  format: z.enum(['rag', 'markdown'])
});

// Domain types
export type JobStatus = 'queued' | 'running' | 'failed' | 'completed';

export type Job = {
  id: string;
  type: 'docs' | 'repo';
  status: JobStatus;
  progress?: number;
  createdAt: string;
  format: 'rag' | 'markdown';
  error?: string;
  files?: FileRec[];
};

export type FileRec = {
  id?: string;
  ord?: number;
  name: string;
  url: string;
  type: 'doc' | 'code';
  text?: string;
  sizeBytes?: number;
};

// Response schemas
export const JobStatusResponse = z.object({
  status: z.enum(['queued', 'running', 'failed', 'completed']),
  progress: z.number().min(0).max(100),
  logs: z.array(z.string())
});

export const JobResultsResponse = z.object({
  files: z.array(z.object({
    name: z.string(),
    url: z.string().url(),
    type: z.enum(['doc', 'code'])
  }))
});