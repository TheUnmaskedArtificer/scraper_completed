import 'package:flutter/material.dart';
import 'package:scraper/models/scraping_job.dart';
import 'package:scraper/widgets/input_section.dart';
import 'package:scraper/widgets/output_section.dart';
import 'package:scraper/widgets/crawler_controls.dart';
import 'package:scraper/widgets/job_progress.dart';
import 'package:scraper/widgets/logs_display.dart';
import 'package:scraper/services/scraping_service.dart';

class ScraperDashboard extends StatefulWidget {
  const ScraperDashboard({super.key});

  @override
  State<ScraperDashboard> createState() => _ScraperDashboardState();
}

class _ScraperDashboardState extends State<ScraperDashboard> {
  final _scrapingService = ScrapingService();
  final _sourceUrlsController = TextEditingController();
  final _basePathController = TextEditingController();
  final _allowedDomainsController = TextEditingController();
  final _githubTokenController = TextEditingController();
  final _userAgentController = TextEditingController(
    text: 'Mozilla/5.0 (compatible; WebScraperBot/1.0)',
  );

  SourceType _sourceType = SourceType.website;
  GitHubScope _githubScope = GitHubScope.docsOnly;
  OutputFormat _outputFormat = OutputFormat.ragJsonl;
  
  int _maxDepth = 3;
  int _chunkSize = 800;
  int _chunkOverlap = 200;
  int _maxPages = 500;
  int _concurrency = 4;
  int _delayMs = 500;
  bool _followSitemaps = true;

  ScrapingJob? _currentJob;
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _scrapingService.addListener(_onJobUpdate);
  }

  @override
  void dispose() {
    _scrapingService.removeListener(_onJobUpdate);
    _sourceUrlsController.dispose();
    _basePathController.dispose();
    _allowedDomainsController.dispose();
    _githubTokenController.dispose();
    _userAgentController.dispose();
    _scrapingService.dispose();
    super.dispose();
  }

  void _onJobUpdate() {
    setState(() {
      _currentJob = _scrapingService.currentJob;
      _logs = _scrapingService.logs;
    });
  }

  Future<void> _validateJob() async {
    final job = _createJob();
    if (job == null) return;

    try {
      final validation = await _scrapingService.validateJob(job);
      if (mounted) {
        _showValidationDialog(validation);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Validation error: $e')),
        );
      }
    }
  }

  Future<void> _runJob() async {
    final job = _createJob();
    if (job == null) return;

    try {
      await _scrapingService.startJob(job);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting job: $e')),
        );
      }
    }
  }

  Future<void> _downloadResults() async {
    if (_currentJob?.status != JobStatus.completed) return;

    try {
      await _scrapingService.downloadResults(_currentJob!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Results downloaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download error: $e')),
        );
      }
    }
  }

  ScrapingJob? _createJob() {
    final urls = _sourceUrlsController.text
        .split('\n')
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();

    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one URL')),
      );
      return null;
    }

    final allowedDomains = _allowedDomainsController.text
        .split('\n')
        .map((domain) => domain.trim())
        .where((domain) => domain.isNotEmpty)
        .toList();

    return ScrapingJob(
      sourceUrls: urls,
      sourceType: _sourceType,
      websiteConfig: _sourceType == SourceType.website
          ? WebsiteConfig(
              basePath: _basePathController.text.trim().isEmpty 
                  ? null 
                  : _basePathController.text.trim(),
              maxDepth: _maxDepth,
              allowedDomains: allowedDomains,
            )
          : null,
      githubConfig: _sourceType == SourceType.github
          ? GitHubConfig(
              scope: _githubScope,
              authToken: _githubTokenController.text.trim().isEmpty
                  ? null
                  : _githubTokenController.text.trim(),
            )
          : null,
      outputConfig: OutputConfig(
        format: _outputFormat,
        chunkSize: _chunkSize,
        chunkOverlap: _chunkOverlap,
      ),
      crawlerConfig: CrawlerConfig(
        maxPages: _maxPages,
        concurrency: _concurrency,
        delayMs: _delayMs,
        respectRobots: true,
        followSitemaps: _followSitemaps,
        userAgent: _userAgentController.text,
      ),
    );
  }

  void _showValidationDialog(Map<String, dynamic> validation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Validation Results'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_sourceType == SourceType.github) ...[
                if (validation["repoName"] != null)
                  Text('Repository: ${validation["repoName"]}'),
                if (validation["isPrivate"] != null) ...[
                  const SizedBox(height: 8),
                  Text('Private: ${validation["isPrivate"]}'),
                ],
                const SizedBox(height: 8),
                Text('Estimated files: ${validation["estimatedFiles"] ?? "Unknown"}'),
              ] else ...[
                Text('Estimated pages: ${validation["estimatedPages"] ?? "Unknown"}'),
                const SizedBox(height: 8),
                Text('Robots.txt status: ${validation["robotsStatus"] ?? "Unknown"}'),
                const SizedBox(height: 8),
                Text('Sitemap found: ${validation["sitemapFound"] ?? "Unknown"}'),
              ],
              if (validation["issues"] != null && validation["issues"].isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Issues:', style: TextStyle(fontWeight: FontWeight.bold)),
                for (String issue in (validation["issues"] as List<dynamic>).cast<String>())
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('• $issue'),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Scraper & Repository Analyzer'),
        actions: [
          IconButton(
            onPressed: _currentJob?.status == JobStatus.running ? null : _validateJob,
            icon: const Icon(Icons.check_circle_outline),
            tooltip: 'Validate',
          ),
          IconButton(
            onPressed: _currentJob?.status == JobStatus.running ? null : _runJob,
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Run',
          ),
          IconButton(
            onPressed: _currentJob?.status == JobStatus.completed ? _downloadResults : null,
            icon: const Icon(Icons.download),
            tooltip: 'Download',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_currentJob != null) ...[
              JobProgress(job: _currentJob!),
              const SizedBox(height: 24),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      InputSection(
                        sourceUrlsController: _sourceUrlsController,
                        basePathController: _basePathController,
                        allowedDomainsController: _allowedDomainsController,
                        githubTokenController: _githubTokenController,
                        sourceType: _sourceType,
                        githubScope: _githubScope,
                        maxDepth: _maxDepth,
                        onSourceTypeChanged: (type) => setState(() => _sourceType = type),
                        onGithubScopeChanged: (scope) => setState(() => _githubScope = scope),
                        onMaxDepthChanged: (depth) => setState(() => _maxDepth = depth),
                      ),
                      const SizedBox(height: 24),
                      OutputSection(
                        outputFormat: _outputFormat,
                        chunkSize: _chunkSize,
                        chunkOverlap: _chunkOverlap,
                        onOutputFormatChanged: (format) => setState(() => _outputFormat = format),
                        onChunkSizeChanged: (size) => setState(() => _chunkSize = size),
                        onChunkOverlapChanged: (overlap) => setState(() => _chunkOverlap = overlap),
                      ),
                      const SizedBox(height: 24),
                      CrawlerControls(
                        maxPages: _maxPages,
                        concurrency: _concurrency,
                        delayMs: _delayMs,
                        followSitemaps: _followSitemaps,
                        userAgentController: _userAgentController,
                        onMaxPagesChanged: (pages) => setState(() => _maxPages = pages),
                        onConcurrencyChanged: (concurrency) => setState(() => _concurrency = concurrency),
                        onDelayChanged: (delay) => setState(() => _delayMs = delay),
                        onFollowSitemapsChanged: (follow) => setState(() => _followSitemaps = follow),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 1,
                  child: LogsDisplay(logs: _logs),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
