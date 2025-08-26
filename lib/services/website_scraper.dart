import 'dart:async';
import 'dart:collection';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:scraper/models/rag_entry.dart';
import 'package:scraper/models/scraping_job.dart';

typedef IsCancelled = bool Function();

class WebsiteScraper {
  final http.Client _client = http.Client();

  // Per-host timing to enforce delay between requests
  final Map<String, DateTime> _lastRequest = {};
  // Per-host mutex to serialize host requests (prevents burst under concurrency)
  final Map<String, Semaphore> _hostLocks = {};

  // Processed URLs for deduplication
  final Set<String> _processedUrls = {};

  // Cached robots.txt rules by host+UA
  final Map<String, _RobotsRules> _robotsCache = {};

  Future<Map<String, dynamic>> validate(ScrapingJob job) async {
    final results = <String, dynamic>{};
    final issues = <String>[];

    for (final url in job.sourceUrls) {
      try {
        final uri = Uri.parse(url);

        // robots.txt check with configured User-Agent
        final robotsResult = await _checkRobotsTxt(
          uri,
          userAgent: job.crawlerConfig.userAgent,
        );
        results['robotsStatus'] =
            (robotsResult['allowed'] == true) ? 'Allowed' : 'Blocked';
        if (robotsResult['allowed'] != true) {
          issues.add('Robots.txt blocks access to $url');
        }

        // sitemap estimate
        final sitemapUrls =
            await _findSitemapUrls(uri, maxUrls: job.crawlerConfig.maxPages);
        results['sitemapFound'] = sitemapUrls.isNotEmpty;
        results['estimatedPages'] =
            sitemapUrls.isNotEmpty ? sitemapUrls.length : 'Unknown (no sitemap)';

        break; // Only validate the first URL
      } catch (e) {
        issues.add('Invalid URL: $url - $e');
      }
    }

    results['issues'] = issues;
    return results;
  }

  Future<List<ProcessedPage>> scrape(
    ScrapingJob job,
    void Function(int, int, int) onProgress,
    void Function(String) addLog, {
    required IsCancelled isCancelled,
  }) async {
    _processedUrls.clear();
    final results = <ProcessedPage>[];
    final failedUrls = <String>[];

    // Seed queue with depth tracking
    final List<_QueueItem> queue = [];
    final seenQueued = <String>{};

    void enqueue(String url, int depth) {
      final normalized = _normalizeUrl(url);
      final config = job.websiteConfig;
      if (normalized == null || config == null) return;
      if (_isAllowedDomain(normalized, config) && _isAllowedPath(normalized, config)) {
        if (!seenQueued.contains(normalized) && !_processedUrls.contains(normalized)) {
          queue.add(_QueueItem(normalized, depth));
          seenQueued.add(normalized);
        }
      }
    }

    // Add user-entered seeds
    for (final url in job.sourceUrls) {
      enqueue(url, 1);
    }

    // Optionally expand from sitemaps (best-effort)
    if (job.crawlerConfig.followSitemaps) {
      for (final url in job.sourceUrls) {
        try {
          final uri = Uri.parse(url);
          final sitemapUrls =
              await _findSitemapUrls(uri, maxUrls: job.crawlerConfig.maxPages);
          for (final sUrl in sitemapUrls) {
            enqueue(sUrl, 1);
          }
        } catch (_) {
          // ignore sitemap failures
        }
      }
    }

    addLog('Starting website scrape with ${queue.length} seed URLs');

    int processedCount = 0;
    int failedCount = 0;
    final globalSemaphore = Semaphore(job.crawlerConfig.concurrency);

    while (queue.isNotEmpty && processedCount < job.crawlerConfig.maxPages) {
      if (isCancelled()) {
        addLog('Cancellation requested. Stopping crawl loop.');
        break;
      }

      final futures = <Future<void>>[];
      final batchSize = job.crawlerConfig.concurrency.clamp(1, queue.length);

      for (int i = 0; i < batchSize && queue.isNotEmpty; i++) {
        final item = queue.removeAt(0);
        final url = item.url;

        if (_processedUrls.contains(url)) continue;

        futures.add(globalSemaphore.acquire().then((_) async {
          try {
            // robots check just-in-time (cached)
            final uri = Uri.parse(url);
            final robotsAllowed = job.crawlerConfig.respectRobots
                ? await _isAllowedByRobots(
                    uri,
                    userAgent: job.crawlerConfig.userAgent,
                  )
                : true;
            if (!robotsAllowed) {
              failedCount++;
              return;
            }

            final res = await _scrapePage(url, job, addLog);
            final page = res?.page;
            final doc = res?.document;

            if (page != null && page.errorMessage == null) {
              // Skip very short/empty content to reduce noise
              if (page.content.trim().length < 30) {
                failedCount++;
              } else {
                results.add(page);
                processedCount++;

                // Depth-limited expansion
                final config = job.websiteConfig;
                if (!isCancelled() && config != null && item.depth < config.maxDepth && doc != null) {
                  final links = _extractLinksFromDocument(url, doc, job);
                  for (final next in links) {
                    enqueue(next, item.depth + 1);
                  }
                }

                addLog('Scraped: $url');
              }
            } else {
              failedCount++;
            }
          } catch (e) {
            failedCount++;
            addLog('Failed to scrape $url: $e');
          } finally {
            globalSemaphore.release();
            onProgress(processedCount, job.crawlerConfig.maxPages, failedCount);
          }
        }));
      }

      await Future.wait(futures);
    }

    addLog(
      'Website scraping completed: $processedCount pages processed, $failedCount failed${isCancelled() ? ' (cancelled)' : ''}',
    );
    return results;
  }

  Future<_PageResult?> _scrapePage(
    String url,
    ScrapingJob job,
    void Function(String) addLog,
  ) async {
    if (_processedUrls.contains(url)) return null;
    _processedUrls.add(url);

    final uri = Uri.parse(url);
    final domain = uri.host;

    // Serialize per-host requests to enforce spacing
    final hostLock = _hostLocks.putIfAbsent(domain, () => Semaphore(1));
    await hostLock.acquire();

    try {
      // Enforce delay between host requests
      final last = _lastRequest[domain];
      final delayMs = job.crawlerConfig.delayMs;
      if (last != null) {
        final elapsed = DateTime.now().difference(last);
        final remaining = delayMs - elapsed.inMilliseconds;
        if (remaining > 0) {
          await Future.delayed(Duration(milliseconds: remaining));
        }
      }

      final headers = {'User-Agent': job.crawlerConfig.userAgent};
      final response = await _getWithRetry(uri, headers: headers, addLog: addLog);

      if (response == null) {
        throw Exception('Request failed after retries');
      }
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final document = html.parse(response.body);
      final title = _extractTitle(document);
      final content = _extractContent(document);
      final headings = _extractHeadings(document);

      return _PageResult(
        page: ProcessedPage(
          url: url,
          title: title,
          content: content,
          headings: headings,
        ),
        document: document,
      );
    } catch (e) {
      return _PageResult(
        page: ProcessedPage(
          url: url,
          title: '',
          content: '',
          headings: const [],
          errorMessage: e.toString(),
        ),
        document: null,
      );
    } finally {
      _lastRequest[domain] = DateTime.now();
      hostLock.release();
    }
  }

  Future<http.Response?> _getWithRetry(
    Uri uri, {
    required Map<String, String> headers,
    int maxRetries = 3,
    void Function(String)? addLog,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final response =
            await _client.get(uri, headers: headers).timeout(const Duration(seconds: 25));

        // Retry on transient and rate-limited responses
        final sc = response.statusCode;
        final transient = sc == 429 || sc == 502 || sc == 503 || sc == 504;
        if (transient) {
          final waitMs = _computeBackoffMs(attempt, response.headers);
          addLog?.call('HTTP backoff ${waitMs}ms for ${uri.toString()} (status $sc)');
          if (attempt > maxRetries) return response;
          await Future.delayed(Duration(milliseconds: waitMs));
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt > maxRetries) {
          addLog?.call('Request timeout after $attempt attempts: ${uri.toString()}');
          return null;
        }
        final waitMs = _computeBackoffMs(attempt, const <String, String>{});
        addLog?.call('Timeout, retrying in ${waitMs}ms: ${uri.toString()}');
        await Future.delayed(Duration(milliseconds: waitMs));
      } catch (e) {
        if (attempt > maxRetries) {
          addLog?.call('Request failed after $attempt attempts: $e');
          return null;
        }
        final waitMs = _computeBackoffMs(attempt, const <String, String>{});
        addLog?.call('Request error, retrying in ${waitMs}ms: $e');
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
  }

  int _computeBackoffMs(int attempt, Map<String, String> headers) {
    final retryAfter = headers['retry-after'];
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null) {
        final ms = seconds * 1000;
        return ms.clamp(1000, 120000).toInt();
      }
    }
    // Exponential backoff with jitter
    final base = 500 * (1 << (attempt - 1));
    final jitter = (base * 0.3).toInt();
    final ms = base + (jitter * ((attempt % 5) + 1));
    return ms.clamp(500, 15000).toInt();
  }

  // ----- Content extraction helpers -----

  String _extractTitle(dom.Document document) {
    final titleElement = document.querySelector('title');
    if (titleElement != null) return titleElement.text.trim();

    final h1Element = document.querySelector('h1');
    if (h1Element != null) return h1Element.text.trim();

    return 'Untitled';
  }

  String _extractContent(dom.Document document) {
    // Prefer likely main content containers
    final mainElement = document.querySelector('main') ??
        document.querySelector('[role="main"]') ??
        document.querySelector('.main-content') ??
        document.querySelector('#main-content') ??
        document.querySelector('article') ??
        document.body;

    if (mainElement == null) return '';

    // Remove navigation/ads/popups etc.
    const unwantedSelectors = [
      'nav',
      'header',
      'footer',
      'aside',
      'script',
      'style',
      '.navigation',
      '.nav',
      '.sidebar',
      // Ads/advertising containers (safer exact-class/id matches)
      '.ads, #ads',
      '.advertisement, #advertisement, .ad-banner, .ad-container',
      // Cookie notices/banners
      '.cookie-notice, #cookie-notice, .cookie-banner, #cookie-banner',
      '.popup',
      '.modal',
    ];

    for (final selector in unwantedSelectors) {
      for (final el in mainElement.querySelectorAll(selector)) {
        el.remove();
      }
    }

    return mainElement.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _extractHeadings(dom.Document document) {
    final headings = <String>[];
    for (int i = 1; i <= 6; i++) {
      final elements = document.querySelectorAll('h$i');
      headings.addAll(elements.map((e) => e.text.trim()));
    }
    return headings.where((h) => h.isNotEmpty).toList();
  }

  List<String> _extractLinksFromDocument(
    String baseUrl,
    dom.Document document,
    ScrapingJob job,
  ) {
    final config = job.websiteConfig;
    if (config == null) return const [];

    final base = Uri.parse(baseUrl);
    final links = <String>[];
    final anchors = document.querySelectorAll('a[href]');
    for (final a in anchors) {
      final raw = a.attributes['href']?.trim();
      if (raw == null || raw.isEmpty) continue;

      final lower = raw.toLowerCase();
      if (lower.startsWith('mailto:') ||
          lower.startsWith('tel:') ||
          lower.startsWith('javascript:') ||
          lower.startsWith('#')) {
        continue;
      }

      Uri? resolved;
      try {
        final candidate = Uri.parse(raw);
        if (!candidate.hasScheme) {
          resolved = base.resolve(raw);
        } else if (candidate.scheme == 'http' || candidate.scheme == 'https') {
          resolved = candidate;
        }
      } catch (_) {
        continue;
      }
      if (resolved == null) continue;

      // Drop fragment
      resolved = resolved.replace(fragment: '');

      final normalized = resolved.toString();
      if (_isAllowedDomain(normalized, config) && _isAllowedPath(normalized, config)) {
        links.add(normalized);
      }
    }

    // Dedupe and cap per page to avoid explosion
    final unique = LinkedHashSet<String>.from(links).toList();
    const cap = 200;
    return unique.length > cap ? unique.sublist(0, cap) : unique;
  }

  // ----- robots.txt and sitemap helpers -----

  Future<bool> _isAllowedByRobots(
    Uri uri, {
    required String userAgent,
  }) async {
    try {
      final rules = await _loadRobotsRules(uri, userAgent: userAgent);
      final path = uri.path.isEmpty ? '/' : uri.path;
      return rules.isAllowed(path);
    } catch (_) {
      // If robots cannot be determined, default allow
      return true;
    }
  }

  Future<_RobotsRules> _loadRobotsRules(
    Uri uri, {
    required String userAgent,
  }) async {
    final host = uri.host;
    final cacheKey = '$host|${userAgent.toLowerCase()}';
    final cached = _robotsCache[cacheKey];
    if (cached != null) return cached;

    final robotsUri = uri.replace(path: '/robots.txt', query: null, fragment: null);
    try {
      final resp = await _client.get(robotsUri);
      if (resp.statusCode == 200) {
        final rules = _RobotsRules.parse(resp.body, userAgent: userAgent);
        _robotsCache[cacheKey] = rules;
        return rules;
      }
    } catch (_) {
      // ignore
    }

    // No robots -> allow all
    final rules = _RobotsRules.allowAll();
    _robotsCache[cacheKey] = rules;
    return rules;
  }

  // For validation UI compatibility (previously returned {'allowed': bool})
  Future<Map<String, bool>> _checkRobotsTxt(
    Uri uri, {
    required String userAgent,
  }) async {
    final allowed = await _isAllowedByRobots(uri, userAgent: userAgent);
    return {'allowed': allowed};
  }

  Future<List<String>> _findSitemapUrls(
    Uri uri, {
    int? maxUrls,
  }) async {
    final discovered = <String>[];

    // 1) Check default /sitemap.xml
    Future<void> fetchAndParseSitemap(Uri sitemapUri) async {
      try {
        final resp = await _client.get(sitemapUri);
        if (resp.statusCode == 200 && resp.body.isNotEmpty) {
          final locs = _extractSitemapLocs(resp.body);
          // If it looks like index (many locs containing 'sitemap')
          final isIndex = RegExp(r'<\s*sitemapindex', caseSensitive: false)
              .hasMatch(resp.body);
          if (isIndex) {
            // Fetch sub-sitemaps
            for (final loc in locs) {
              if (maxUrls != null && discovered.length >= maxUrls) break;
              final subUri = Uri.parse(loc);
              await fetchAndParseSitemap(subUri);
              if (maxUrls != null && discovered.length >= maxUrls) break;
            }
          } else {
            for (final loc in locs) {
              if (maxUrls != null && discovered.length >= maxUrls) break;
              discovered.add(loc);
            }
          }
        }
      } catch (_) {
        // ignore
      }
    }

    final defaultSitemap = uri.replace(path: '/sitemap.xml', query: null, fragment: null);
    await fetchAndParseSitemap(defaultSitemap);

    // 2) Also look for "Sitemap:" lines in robots.txt
    try {
      final robotsUri = uri.replace(path: '/robots.txt', query: null, fragment: null);
      final resp = await _client.get(robotsUri);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final lines = resp.body.split('\n');
        for (final line in lines) {
          final idx = line.toLowerCase().indexOf('sitemap:');
          if (idx >= 0) {
            final rest = line.substring(idx + 8).trim();
            if (rest.isNotEmpty) {
              final sm = rest.split(RegExp(r'\s+')).first.trim();
              Uri? smUri;
              try {
                smUri = Uri.parse(sm);
                if (!smUri.hasScheme) {
                  smUri = uri.replace(path: sm);
                }
              } catch (_) {
                smUri = null;
              }
              if (smUri != null) {
                await fetchAndParseSitemap(smUri);
              }
            }
          }
          if (maxUrls != null && discovered.length >= maxUrls) break;
        }
      }
    } catch (_) {
      // ignore
    }

    // Dedupe and bound
    final set = LinkedHashSet<String>.from(discovered);
    final list = set.toList();
    if (maxUrls != null && list.length > maxUrls) {
      return list.sublist(0, maxUrls);
    }
    return list;
  }

  List<String> _extractSitemapLocs(String xml) {
    // Lightweight extraction of <loc> elements from XML or HTML-ish content
    final regex = RegExp(r'<\s*loc[^>]*>\s*([^<\s]+)\s*<\s*/\s*loc\s*>',
        caseSensitive: false);
    final matches = regex.allMatches(xml);
    final urls = <String>[];
    for (final m in matches) {
      final url = m.group(1);
      if (url != null && url.trim().isNotEmpty) {
        urls.add(url.trim());
      }
    }
    return urls;
  }

  // ----- URL and policy helpers -----

  String? _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
        // Remove fragments, normalize
        return uri.replace(fragment: '').toString();
      }
    } catch (_) {
      // Invalid URL
    }
    return null;
  }

  bool _isAllowedDomain(String url, WebsiteConfig config) {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host;

      if (config.allowedDomains.isEmpty) {
        return true; // No restrictions
      }

      return config.allowedDomains.any(
        (allowedDomain) =>
            domain == allowedDomain || domain.endsWith('.$allowedDomain'),
      );
    } catch (_) {
      return false;
    }
  }

  bool _isAllowedPath(String url, WebsiteConfig config) {
    if (config.basePath == null || config.basePath!.trim().isEmpty) return true;
    try {
      final uri = Uri.parse(url);
      final basePath = config.basePath!.trim();
      final normalizedBase =
          basePath.startsWith('/') ? basePath : '/$basePath';
      final path = uri.path.isEmpty ? '/' : uri.path;
      return path == normalizedBase || path.startsWith('$normalizedBase/');
    } catch (_) {
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

// ----- Internal helpers and data structures -----

class _QueueItem {
  final String url;
  final int depth;
  const _QueueItem(this.url, this.depth);
}

class _PageResult {
  final ProcessedPage page;
  final dom.Document? document;
  const _PageResult({required this.page, required this.document});
}

class _RobotsRules {
  final List<String> allow;
  final List<String> disallow;

  _RobotsRules({required this.allow, required this.disallow});

  static _RobotsRules allowAll() => _RobotsRules(allow: const [''], disallow: const <String>[]);

  // Very simple robots parser: pick the best-matching user-agent group
  // then collect Allow/Disallow rules. Matching is prefix-based; longest rule wins,
  // with Allow preferred on equal length (common crawler behavior).
  static _RobotsRules parse(String robotsTxt, {required String userAgent}) {
    final lines = robotsTxt.split('\n');

    final groups = <String, List<_Rule>>{};
    String currentAgent = '*';

    void startGroup(String agent) {
      currentAgent = agent.isEmpty ? '*' : agent.toLowerCase();
      groups.putIfAbsent(currentAgent, () => <_Rule>[]);
    }

    startGroup('*');

    for (var raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final parts = line.split(':');
      if (parts.length < 2) continue;

      final key = parts[0].trim().toLowerCase();
      final value = parts.sublist(1).join(':').trim();

      if (key == 'user-agent') {
        startGroup(value);
      } else if (key == 'allow') {
        groups[currentAgent]!.add(_Rule(value, true));
      } else if (key == 'disallow') {
        groups[currentAgent]!.add(_Rule(value, false));
      }
      // Ignore Crawl-delay and others for now
    }

    // Choose group: exact UA match first, else '*'
    final uaLower = userAgent.toLowerCase();
    List<_Rule>? rules;
    for (final k in groups.keys) {
      if (k != '*' && uaLower.contains(k)) {
        rules = groups[k];
        break;
      }
    }
    rules ??= groups['*'] ?? <_Rule>[];

    final allow = <String>[];
    final disallow = <String>[];
    for (final r in rules) {
      if (r.isAllow) {
        allow.add(r.path);
      } else {
        disallow.add(r.path);
      }
    }
    return _RobotsRules(allow: allow, disallow: disallow);
  }

  bool isAllowed(String path) {
    String norm = path.isEmpty ? '/' : path;

    int bestAllowLen = -1;
    int bestDisallowLen = -1;

    for (final a in allow) {
      if (a.isEmpty) {
        bestAllowLen = bestAllowLen < 0 ? 0 : bestAllowLen;
        continue;
      }
      if (norm.startsWith(a)) {
        if (a.length > bestAllowLen) bestAllowLen = a.length;
      }
    }

    for (final d in disallow) {
      if (d.isEmpty) continue;
      if (norm.startsWith(d)) {
        if (d.length > bestDisallowLen) bestDisallowLen = d.length;
      }
    }

    if (bestDisallowLen < 0 && bestAllowLen < 0) return true;
    if (bestAllowLen >= bestDisallowLen) return true;
    return false;
  }
}

class _Rule {
  final String path;
  final bool isAllow;
  _Rule(String rawPath, this.isAllow) : path = _normalizeRulePath(rawPath);

  static String _normalizeRulePath(String p) {
    var s = p.trim();
    if (s.isEmpty) return s;
    // Basic wildcard neutralization (very naive)
    s = s.replaceAll('*', '');
    // Ensure leading slash
    if (!s.startsWith('/')) s = '/$s';
    return s;
  }
}