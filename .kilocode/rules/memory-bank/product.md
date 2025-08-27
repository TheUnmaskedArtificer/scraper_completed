# API Contract

## Endpoints

```http
POST /api/jobs
{
  urls: string[],
  type: 'docs' | 'repo',
  depth: int = 3,
  maxPages: int = 100,
  format: 'rag' | 'markdown'
} -> { jobId: string }
```

```http
GET /api/jobs/:id/status
-> {
  status: 'queued' | 'running' | 'failed' | 'completed',
  progress: 0-100,
  logs: string[]
}
```

```http
GET /api/jobs/:id/results
-> { files: { name: string, url: string, type: string }[] }
```

```http
GET /api/jobs
-> { jobs: { id: string, status: string, createdAt: timestamp, type: string, format: string }[] }
```

## Error Handling
All endpoints return standard HTTP error codes (400, 404, 500) with consistent error format:
```json
{
  "error": {
    "code": "string",
    "message": "string",
    "details": "object"
  }
}