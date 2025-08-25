import 'dart:async';
import 'dart:collection';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:scraper/models/scraping_job.dart';
import 'package:scraper/models/rag_entry.dart';

typedef IsCancelled = bool Function();

class WebsiteScraper {
  final http.Client _client = http.Client();
  final Map<String, DateTime> _lastRequest = {};
  final Set<String> _processedUrls = {};

  Future<Map<String, dynamic>> validate(ScrapingJob job) async {
    final results = <String, dynamic>{};
    final issues = <String>[];

    for (final url in job.sourceUrls) {
      try {
        final uri = Uri.parse(url);
        
        // Check robots.txt
        final robotsResult = await _checkRobotsTxt(uri);
        results['robotsStatus'] = (robotsResult['allowed'] == true) ? 'Allowed' : 'Blocked';
        if (robotsResult['allowed'] != true) {
          issues.add('Robots.txt blocks access to $url');
        }

        // Check sitemap
        final sitemapUrls = await _findSitemapUrls(uri);
        results['sitemapFound'] = sitemapUrls.isNotEmpty;
        
        // Estimate page count
        if (sitemapUrls.isNotEmpty) {
          results['estimatedPages'] = sitemapUrls.length;
        } else {
          results['estimatedPages'] = 'Unknown (no sitemap)';
        }

        break; // Only check first URL for validation
      } catch (e) {
        issues.add('Invalid URL: $url - $e');
      }
    }

    results['issues'] = issues;
    return results;
  }

  Future<List<ProcessedPage>> scrape(
    ScrapingJob job,
    Function(int, int, int) onProgress,
    Function(String) addLog, {
    required IsCancelled isCancelled,
  }) async {
    _processedUrls.clear();
    final results = <ProcessedPage>[];
    final urlQueue = <String>[];
    final failedUrls = <String>[];

    // Initialize queue
    for (final url in job.sourceUrls) {
      final normalizedUrl = _normalizeUrl(url);
      final config = job.websiteConfig;
      if (normalizedUrl != null && config != null && _isAllowedDomain(normalizedUrl, config)) {
        urlQueue.add(normalizedUrl);
      }
    }

    addLog('Starting website scrape with ${urlQueue.length} seed URLs');

    int processedCount = 0;
    final semaphore = Semaphore(job.crawlerConfig.concurrency);

    while (urlQueue.isNotEmpty && processedCount < job.crawlerConfig.maxPages) {
      if (isCancelled()) {
        addLog('Cancellation requested. Stopping crawl loop.');
        break;
      }

      final batch = <Future>[];
      final batchSize = job.crawlerConfig.concurrency.clamp(1, urlQueue.length);

      for (int i = 0; i < batchSize && urlQueue.isNotEmpty; i++) {
        if (isCancelled()) break;

        final url = urlQueue.removeAt(0);
        if (_processedUrls.contains(url)) continue;

        batch.add(
          semaphore.acquire().then((_) async {
            if (isCancelled()) {
              semaphore.release();
              return;
            }
            try {
              final page = await _scrapePage(url, job);
              if (page != null && (page.errorMessage == null || page.errorMessage!.isEmpty)) {
                results.add(page);
                processedCount++;
                
                // Extract links for further crawling
                final config = job.websiteConfig;
                if (!isCancelled() && config != null && config.maxDepth > 1) {
                  final links = await _extractLinks(url, page.content, job);
                  urlQueue.addAll(links);
                }
                
                addLog('Scraped: $url');
              } else {
                failedUrls.add(url);
              }
            } catch (e) {
              failedUrls.add(url);
              addLog('Failed to scrape $url: $e');
            } finally {
              semaphore.release();
              onProgress(processedCount, job.crawlerConfig.maxPages, failedUrls.length);
            }
          }),
        );
      }

      await Future.wait(batch);
    }

    addLog('Website scraping completed: $processedCount pages processed, ${failedUrls.length} failed${isCancelled() ? ' (cancelled)' : ''}');
    return results;
  }

  Future<ProcessedPage?> _scrapePage(String url, ScrapingJob job) async {
    if (_processedUrls.contains(url)) return null;
    _processedUrls.add(url);

    // Rate limiting
    final domain = Uri.parse(url).host;
    final lastRequest = _lastRequest[domain];
    if (lastRequest != null) {
      final elapsed = DateTime.now().difference(lastRequest);
      if (elapsed.inMilliseconds < job.crawlerConfig.delayMs) {
        await Future.delayed(
          Duration(milliseconds: job.crawlerConfig.delayMs - elapsed.inMilliseconds),
        );
      }
    }
    _lastRequest[domain] = DateTime.now();

    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': job.crawlerConfig.userAgent},
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final document = html.parse(response.body);
      final title = _extractTitle(document);
      final content = _extractContent(document);
      final headings = _extractHeadings(document);

      return ProcessedPage(
        url: url,
        title: title,
        content: content,
        headings: headings,
      );
    } catch (e) {
      return ProcessedPage(
        url: url,
        title: '',
        content: '',
        headings: [],
        errorMessage: e.toString(),
      );
    }
  }

  String _extractTitle(dom.Document document) {
    final titleElement = document.querySelector('title');
    if (titleElement != null) return titleElement.text.trim();

    final h1Element = document.querySelector('h1');
    if (h1Element != null) return h1Element.text.trim();

    return 'Untitled';
  }

  String _extractContent(dom.Document document) {
    // Try to find main content area
    final mainElement = document.querySelector('main') ??
        document.querySelector('[role="main"]') ??
        document.querySelector('.main-content') ??
        document.querySelector('#main-content') ??
        document.querySelector('article') ??
        document.body;

    if (mainElement == null) return '';

    // Remove unwanted elements
    final unwantedSelectors = [
      'nav', 'header', 'footer', 'aside', 'script', 'style',
      '.navigation', '.nav', '.sidebar', '.ads', '.advertisement',
      '.cookie-notice', '.popup', '.modal'
    ];

    for (final selector in unwantedSelectors) {
      mainElement.querySelectorAll(selector).forEach((element) {
        element.remove();
      });
    }

    return mainElement.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _extractHeadings(dom.Document document) {
    final headings = <String>[];
    for (int i = 1; i <= 6; i++) {
      final elements = document.querySelectorAll('h$i');
      headings.addAll(elements.map((e) => e.text.trim()));
    }
    return headings.where((h) => h.isNotEmpty).toList();
  }

  Future<List<String>> _extractLinks(String baseUrl, String content, ScrapingJob job) async {
    // This is a simplified implementation
    // In a full implementation, you'd parse the HTML and extract all links
    return [];
  }

  Future<Map<String, bool>> _checkRobotsTxt(Uri uri) async {
    try {
      final robotsUrl = uri.replace(path: '/robots.txt');
      final response = await _client.get(robotsUrl);
      
      if (response.statusCode == 200) {
        final robotsContent = response.body;
        // Simplified robots.txt parsing
        // In reality, you'd need a proper parser
        final disallowed = robotsContent.contains('Disallow: /');
        return {'allowed': !disallowed};
      }
    } catch (e) {
      // If robots.txt doesn't exist, assume allowed
    }
    
    return {'allowed': true};
  }

  Future<List<String>> _findSitemapUrls(Uri uri) async {
    try {
      final sitemapUrl = uri.replace(path: '/sitemap.xml');
      final response = await _client.get(sitemapUrl);
      
      if (response.statusCode == 200) {
        final document = html.parse(response.body);
        final urls = document.querySelectorAll('url loc')
            .map((e) => e.text.trim())
            .where((url) => url.isNotEmpty)
            .toList();
        return urls;
      }
    } catch (e) {
      // Sitemap not found or error
    }
    
    return [];
  }

  String? _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return uri.toString();
      }
    } catch (e) {
      // Invalid URL
    }
    return null;
  }

  bool _isAllowedDomain(String url, WebsiteConfig config) {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host;
      
      // Check if it matches allowed domains
      if (config.allowedDomains.isEmpty) {
        return true; // No restrictions
      }
      
      return config.allowedDomains.any((allowedDomain) =>
          domain == allowedDomain || domain.endsWith('.$allowedDomain'));
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}

class Semaphore {
  final int maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(this.maxCount) : _currentCount = maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}