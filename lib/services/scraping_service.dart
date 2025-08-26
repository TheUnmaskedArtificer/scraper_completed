import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:scraper/models/scraping_job.dart';
import 'package:scraper/models/rag_entry.dart';
import 'package:scraper/services/website_scraper.dart';
import 'package:scraper/services/github_scraper.dart';
import 'package:scraper/services/export_service.dart';

class ScrapingService extends ChangeNotifier {
  ScrapingJob? _currentJob;
  final List<String> _logs = [];
  bool _cancelRequested = false;

  final _websiteScraper = WebsiteScraper();
  final _githubScraper = GitHubScraper();
  final _exportService = ExportService();

  // Throttled notifications for logs to reduce rebuild pressure
  Timer? _logNotifyTimer;
  DateTime _lastLogNotify = DateTime.fromMillisecondsSinceEpoch(0);
  bool _logNotifyScheduled = false;

  static const String _cancelledByUserMessage = 'Cancelled by user';

  ScrapingJob? get currentJob => _currentJob;
  List<String> get logs => List.unmodifiable(_logs);

  Future<Map<String, dynamic>> validateJob(ScrapingJob job) async {
    _addLog('Validating job...');

    try {
      if (job.sourceType == SourceType.website) {
        return await _websiteScraper.validate(job);
      } else {
        return await _githubScraper.validate(job);
      }
    } catch (e) {
      _addLog('Validation error: $e');
      rethrow;
    }
  }

  Future<void> startJob(ScrapingJob job) async {
    if (_currentJob?.status == JobStatus.running) {
      throw Exception('Another job is already running');
    }

    _currentJob = job;
    _cancelRequested = false;
    _clearLogs();
    _addLog('Starting job: ${job.id}');

    job.status = JobStatus.running;
    notifyListeners();

    try {
      List<ProcessedPage> results;

      if (job.sourceType == SourceType.website) {
        results = await _websiteScraper.scrape(
          job,
          _onProgress,
          _addLog,
          isCancelled: () => _cancelRequested,
        );
      } else {
        results = await _githubScraper.scrape(
          job,
          _onProgress,
          _addLog,
          isCancelled: () => _cancelRequested,
        );
      }

      if (_cancelRequested) {
        _markJobCancelled(job);
        return;
      }

      await _exportService.generateExports(job, results);

      job.status = JobStatus.completed;
      _addLog('Job completed successfully');
    } catch (e) {
      job.status = JobStatus.failed;
      job.errorMessage = e.toString();
      _addLog('Job failed: $e');
    } finally {
      notifyListeners();
    }
  }

  Future<void> downloadResults(ScrapingJob job) async {
    if (job.status != JobStatus.completed) {
      throw Exception('Job must be completed to download results');
    }

    _addLog('Generating download...');
    await _exportService.downloadResults(job);
    _addLog('Download ready');
  }

  void cancelJob() {
    if (_currentJob?.status == JobStatus.running) {
      _cancelRequested = true;
      _addLog('Cancellation requested by user');
      notifyListeners();
    }
  }

  void _onProgress(int processed, int total, int failed) {
    final job = _currentJob;
    if (job != null) {
      job.processedPages = processed;
      job.totalPages = total;
      job.failedPages = failed;
      notifyListeners();
    }
  }

  void _markJobCancelled(ScrapingJob job) {
    job.status = JobStatus.failed; // keep existing model semantics
    job.errorMessage = _cancelledByUserMessage;
    _addLog('Job cancelled by user');
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] $message';
    _logs.add(logEntry);

    // Keep only last 100 log entries
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }

    if (kDebugMode) {
      print(logEntry);
    }

    _scheduleLogNotify();
  }

  void _scheduleLogNotify() {
    const intervalMs = 200; // coalesce UI updates ~5/sec
    final now = DateTime.now();
    final elapsed = now.difference(_lastLogNotify).inMilliseconds;

    if (elapsed >= intervalMs) {
      _lastLogNotify = now;
      notifyListeners();
      return;
    }

    if (_logNotifyScheduled) return;

    _logNotifyScheduled = true;
    final wait = Duration(milliseconds: intervalMs - elapsed);
    _logNotifyTimer?.cancel();
    _logNotifyTimer = Timer(wait, () {
      _logNotifyScheduled = false;
      _lastLogNotify = DateTime.now();
      notifyListeners();
    });
  }

  void _clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _websiteScraper.dispose();
    _githubScraper.dispose();
    _logNotifyTimer?.cancel();
    super.dispose();
  }
}