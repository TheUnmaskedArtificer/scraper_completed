import 'package:scraper/models/scraping_job.dart';

class SampleData {
  static List<Map<String, dynamic>> getSampleJobs() {
    return [
      {
        'name': 'Documentation Site',
        'urls': ['https://flutter.dev/docs'],
        'sourceType': SourceType.website,
        'websiteConfig': WebsiteConfig(
          basePath: '/docs',
          maxDepth: 3,
          allowedDomains: ['flutter.dev'],
        ),
        'outputFormat': OutputFormat.both,
      },
      {
        'name': 'GitHub Repository - Docs Only',
        'urls': ['https://github.com/flutter/flutter'],
        'sourceType': SourceType.github,
        'githubConfig': GitHubConfig(scope: GitHubScope.docsOnly),
        'outputFormat': OutputFormat.ragJsonl,
      },
      {
        'name': 'GitHub Repository - Full',
        'urls': ['https://github.com/microsoft/vscode'],
        'sourceType': SourceType.github,
        'githubConfig': GitHubConfig(scope: GitHubScope.fullRepo),
        'outputFormat': OutputFormat.readableMarkdown,
      },
    ];
  }

  static ScrapingJob createSampleJob(Map<String, dynamic> config) {
    return ScrapingJob(
      sourceUrls: List<String>.from(config['urls']),
      sourceType: config['sourceType'],
      websiteConfig: config['websiteConfig'],
      githubConfig: config['githubConfig'],
      outputConfig: OutputConfig(
        format: config['outputFormat'],
        chunkSize: 800,
        chunkOverlap: 200,
      ),
      crawlerConfig: CrawlerConfig(
        maxPages: 100, // Reduced for demo
        concurrency: 2,
        delayMs: 1000,
      ),
    );
  }

  static String getValidationInstructions() {
    return '''
# Sample Test Cases

## Website Scraping
1. **Documentation Site Example**:
   - URL: https://flutter.dev/docs
   - Base Path: /docs
   - Expected: ~50 pages, respects robots.txt
   
2. **API Documentation**:
   - URL: https://api.github.com
   - Expected: JSON responses, structured data

## GitHub Repository
1. **Docs Only Mode**:
   - URL: https://github.com/flutter/flutter
   - Expected: Only documentation files (.md, /docs/)
   
2. **Full Repository**:
   - URL: https://github.com/microsoft/vscode
   - Expected: All text files, larger dataset

## Output Formats
- **RAG JSONL**: Chunked data with metadata
- **Readable Markdown**: Clean .md files
- **Readable HTML**: Formatted HTML with CSS
- **Both**: Combined output

## Rate Limiting
- Respects robots.txt (non-negotiable)
- Implements delays between requests
- Handles 429/5xx with backoff
- Maximum 2 retries per URL
''';
  }
}