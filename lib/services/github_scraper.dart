import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:scraper/models/scraping_job.dart';
import 'package:scraper/models/rag_entry.dart';

typedef IsCancelled = bool Function();

class GitHubScraper {
  final http.Client _client = http.Client();
  static const String apiBase = 'https://api.github.com';

  static const int _defaultMaxFileBytes = 1048576; // 1 MB default
  static const Duration _defaultTimeout = Duration(seconds: 20);

  Map<String, String> _buildHeaders(String? token) {
    final headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'ScraperApp/1.0',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response?> _getWithRetry(
    Uri uri, {
    required Map<String, String> headers,
    int maxRetries = 3,
    Function(String)? addLog,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final response = await _client.get(uri, headers: headers).timeout(_defaultTimeout);

        // Surface rate-limit context when available
        final remaining = response.headers['x-ratelimit-remaining'];
        final reset = response.headers['x-ratelimit-reset'];
        if (remaining != null) {
          final remInt = int.tryParse(remaining);
          if (remInt != null && remInt <= 100) {
            final resetTs = reset != null ? int.tryParse(reset) : null;
            final resetInSec = resetTs != null
                ? (resetTs - (DateTime.now().millisecondsSinceEpoch ~/ 1000))
                : null;
            addLog?.call(
              'GitHub rate remaining: $remInt${resetInSec != null ? ' (resets in ${resetInSec}s)' : ''} for ${uri.path}',
            );
          }
        }

        final isRateLimited =
            response.statusCode == 429 || (response.statusCode == 403 && remaining == '0');
        final isTransient = response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504;

        if (isRateLimited || isTransient) {
          final waitMs = _computeBackoffMs(attempt, response.headers);
          addLog?.call(
              'GitHub backoff ${waitMs}ms for ${uri.path} (status ${response.statusCode})');
          if (attempt > maxRetries) return response;
          await Future.delayed(Duration(milliseconds: waitMs));
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt > maxRetries) {
          addLog?.call('GitHub request timeout after $attempt attempts: ${uri.path}');
          return null;
        }
        final waitMs = _computeBackoffMs(attempt, const <String, String>{});
        addLog?.call('GitHub timeout, retrying in ${waitMs}ms: ${uri.path}');
        await Future.delayed(Duration(milliseconds: waitMs));
      } catch (e) {
        if (attempt > maxRetries) {
          addLog?.call('GitHub request failed after $attempt attempts: $e');
          return null;
        }
        final waitMs = _computeBackoffMs(attempt, const <String, String>{});
        addLog?.call('GitHub request error, retrying in ${waitMs}ms: $e');
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
        return ms.clamp(1000, 120000);
      }
    }
    final remaining = headers['x-ratelimit-remaining'];
    final reset = headers['x-ratelimit-reset'];
    if (remaining == '0' && reset != null) {
      final resetEpoch = int.tryParse(reset);
      if (resetEpoch != null) {
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final deltaMs = (resetEpoch - nowSec) * 1000;
        if (deltaMs > 0) return deltaMs.clamp(1000, 300000);
      }
    }
    final base = 500 * (1 << (attempt - 1));
    final jitter = (base * 0.3).toInt();
    final ms = base + (jitter * ((attempt % 5) + 1));
    return ms.clamp(500, 15000);
  }

  Future<Map<String, dynamic>?> _getRepositoryInfoAuth(
    String owner,
    String repo,
    String? token,
    Function(String)? addLog,
  ) async {
    try {
      final uri = Uri.parse('$apiBase/repos/$owner/$repo');
      final response = await _getWithRetry(
        uri,
        headers: _buildHeaders(token),
        addLog: addLog,
      );
      if (response != null && response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> _getFileTreeAuth(
    String owner,
    String repo,
    String branch,
    GitHubConfig config,
    String? token,
    int effectiveMaxBytes,
    Function(String)? addLog,
  ) async {
    try {
      final uri = Uri.parse('$apiBase/repos/$owner/$repo/git/trees/$branch?recursive=1');
      final response = await _getWithRetry(
        uri,
        headers: _buildHeaders(token),
        addLog: addLog,
      );
      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tree = (data['tree'] as List).cast<Map>();

        final excludes = <String>[
          '.git/',
          'node_modules/',
          'vendor/',
          'dist/',
          'build/',
          'target/',
          'bin/',
          'obj/',
          'pods/',
          'third_party/',
          'submodules/',
        ];

        final filtered = tree
            .where((item) => item['type'] == 'blob')
            .map((item) => <String, dynamic>{
                  'path': item['path'] as String,
                  'sha': item['sha'],
                  'size': item['size'] ?? 0,
                })
            .where((file) {
              final p = (file['path'] as String);
              final lower = p.toLowerCase();
              if (excludes.any((ex) => lower.startsWith(ex) || lower.contains('/$ex'))) {
                return false;
              }
              final size = (file['size'] is int)
                  ? file['size'] as int
                  : int.tryParse('${file['size']}') ?? 0;
              if (size >= effectiveMaxBytes) return false;
              return _shouldIncludeFile(p, config);
            })
            .toList();

        return filtered.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<String?> _getFileContentAuth(
    String owner,
    String repo,
    String path,
    String? token,
    Function(String)? addLog,
  ) async {
    try {
      final uri = Uri.parse('$apiBase/repos/$owner/$repo/contents/$path');
      final response = await _getWithRetry(
        uri,
        headers: _buildHeaders(token),
        addLog: addLog,
      );
      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = data['content'];
        if (content is String) {
          return utf8.decode(base64Decode(content.replaceAll('\n', '')));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> validate(ScrapingJob job) async {
    final results = <String, dynamic>{};
    final issues = <String>[];

    for (final url in job.sourceUrls) {
      try {
        final repoInfo = _parseGitHubUrl(url);
        if (repoInfo == null) {
          issues.add('Invalid GitHub URL: $url');
          continue;
        }

        final owner = repoInfo['owner'];
        final repo = repoInfo['repo'];
        final config = job.githubConfig;

        if (owner == null || repo == null || config == null) {
          issues.add('Invalid configuration for: $url');
          continue;
        }

        // Check if repository exists and is accessible
        final repoData = await _getRepositoryInfoAuth(owner, repo, config.authToken, null);
        if (repoData == null) {
          issues.add('Repository not found or not accessible: $url');
          continue;
        }

        results['repoName'] = '$owner/$repo';
        results['isPrivate'] = repoData['private'] ?? false;

        // Get file tree to estimate file count
        final defaultBranch = repoData['default_branch'] ?? 'main';
        results['defaultBranch'] = defaultBranch;
        final effectiveMaxBytes = config.maxFileBytes ?? _defaultMaxFileBytes;
        final fileTree = await _getFileTreeAuth(
          owner,
          repo,
          defaultBranch,
          config,
          config.authToken,
          effectiveMaxBytes,
          null,
        );
        results['estimatedFiles'] = fileTree.length;

        break; // Only validate first URL
      } catch (e) {
        issues.add('Error validating $url: $e');
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
    final results = <ProcessedPage>[];
    int processedCount = 0;
    int failedCount = 0;

    for (final url in job.sourceUrls) {
      if (isCancelled()) {
        addLog('Cancellation requested before repository loop. Stopping.');
        break;
      }

      final repoInfo = _parseGitHubUrl(url);
      if (repoInfo == null) {
        addLog('Invalid GitHub URL: $url');
        failedCount++;
        continue;
      }

      final owner = repoInfo["owner"];
      final repo = repoInfo["repo"];
      final config = job.githubConfig;

      if (owner == null || repo == null || config == null) {
        addLog('Invalid configuration for GitHub repository: $url');
        failedCount++;
        continue;
      }

      addLog('Scraping GitHub repository: $owner/$repo');

      try {
        final repoData = await _getRepositoryInfoAuth(owner, repo, config.authToken, addLog);
        final defaultBranch = repoData?['default_branch'] ?? 'main';
        final effectiveMaxBytes = config.maxFileBytes ?? _defaultMaxFileBytes;
        final fileTree = await _getFileTreeAuth(
          owner,
          repo,
          defaultBranch,
          config,
          config.authToken,
          effectiveMaxBytes,
          addLog,
        );
        final totalToProcess = fileTree.length > job.crawlerConfig.maxPages
            ? job.crawlerConfig.maxPages
            : fileTree.length;
        job.totalPages = totalToProcess;
        onProgress(processedCount, totalToProcess, failedCount);
        addLog('Found ${fileTree.length} files to process (processing up to $totalToProcess)');

        for (final file in fileTree) {
          if (isCancelled()) {
            addLog('Cancellation requested. Stopping file processing.');
            break;
          }
          if (processedCount >= job.crawlerConfig.maxPages) break;

          try {
            final content = await _getFileContentAuth(
              owner,
              repo,
              file['path'],
              config.authToken,
              addLog,
            );
            if (content != null) {
              final page = ProcessedPage(
                url: '$url/blob/$defaultBranch/${file["path"]}',
                title: _getFileTitle(file["path"]),
                content: _processContent(content, file["path"]),
                headings: _extractMarkdownHeadings(content, file["path"]),
              );

              results.add(page);
              processedCount++;
              addLog('Processed: ${file["path"]}');
            } else {
              failedCount++;
              addLog('Failed to get content for: ${file["path"]}');
            }
          } catch (e) {
            failedCount++;
            addLog('Error processing ${file["path"]}: $e');
          }

          onProgress(processedCount, job.totalPages, failedCount);
        }
      } catch (e) {
        addLog('Error scraping repository $url: $e');
        failedCount++;
      }
    }

    addLog(
        'GitHub scraping completed: $processedCount files processed, $failedCount failed${isCancelled() ? ' (cancelled)' : ''}');
    return results;
  }

  Map<String, String>? _parseGitHubUrl(String url) {
    final uri = Uri.parse(url);
    if (uri.host != 'github.com') return null;

    final segments = uri.pathSegments;
    if (segments.length < 2) return null;

    return {
      'owner': segments[0],
      'repo': segments[1],
    };
  }

  Future<Map<String, dynamic>?> _getRepositoryInfo(String owner, String repo) async {
    try {
      final response = await _client.get(
        Uri.parse('$apiBase/repos/$owner/$repo'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      // Error getting repo info
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _getFileTree(
      String owner, String repo, String branch, GitHubConfig config) async {
    try {
      final response = await _client.get(
        Uri.parse('$apiBase/repos/$owner/$repo/git/trees/$branch?recursive=1'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tree = data['tree'] as List;

        return tree
            .where((item) => item['type'] == 'blob')
            .map((item) => {
                  "path": item["path"],
                  "sha": item["sha"],
                  "size": item["size"],
                })
            .where((file) => _shouldIncludeFile(file["path"], config))
            .toList();
      }
    } catch (e) {
      // Error getting file tree
    }
    return [];
  }

  bool _shouldIncludeFile(String path, GitHubConfig config) {
    final lowerPath = path.toLowerCase();
    final basename = lowerPath.split('/').last;

    if (config.scope == GitHubScope.docsOnly) {
      // Always include key docs files regardless of extension
      final docsNames = ['readme', 'changelog', 'license', 'licence', 'contributing'];
      final baseNoExt = basename.replaceAll(RegExp(r'\.[^.]*$'), '');
      if (docsNames.contains(baseNoExt)) return true;

      // Include common docs locations and extensions
      if (lowerPath.startsWith('docs/') ||
          lowerPath.contains('/docs/') ||
          lowerPath.startsWith('documentation/') ||
          lowerPath.contains('/documentation/') ||
          lowerPath.contains('/guide/') ||
          lowerPath.contains('/guides/') ||
          lowerPath.contains('/manual/') ||
          lowerPath.endsWith('.md') ||
          lowerPath.endsWith('.mdx') ||
          lowerPath.endsWith('.html') ||
          lowerPath.endsWith('.htm')) {
        return true;
      }
      return false;
    } else {
      // Full repo: include text files, exclude binaries via extension allowlist
      final textExtensions = [
        '.md',
        '.mdx',
        '.txt',
        '.html',
        '.htm',
        '.rst',
        '.adoc',
        '.js',
        '.ts',
        '.jsx',
        '.tsx',
        '.py',
        '.java',
        '.cpp',
        '.c',
        '.h',
        '.hpp',
        '.cs',
        '.php',
        '.rb',
        '.go',
        '.rs',
        '.swift',
        '.kt',
        '.scala',
        '.clj',
        '.hs',
        '.ml',
        '.elm',
        '.dart',
        '.json',
        '.yaml',
        '.yml',
        '.toml',
        '.ini',
        '.cfg',
        '.conf',
        '.xml',
        '.svg',
        '.css',
        '.scss',
        '.sass',
        '.less',
      ];

      // Also include key root files without extension changes (README, LICENSE, etc.)
      final baseNoExt = basename.replaceAll(RegExp(r'\.[^.]*$'), '');
      final keyDocs = ['readme', 'changelog', 'license', 'licence', 'contributing'];
      if (keyDocs.contains(baseNoExt)) return true;

      return textExtensions.any((ext) => lowerPath.endsWith(ext));
    }
  }

  Future<String?> _getFileContent(String owner, String repo, String path) async {
    try {
      final response = await _client.get(
        Uri.parse('$apiBase/repos/$owner/$repo/contents/$path'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content'];
        if (content != null) {
          return utf8.decode(base64Decode(content.replaceAll('\n', '')));
        }
      }
    } catch (e) {
      // Error getting file content
    }
    return null;
  }

  String _getFileTitle(String path) {
    final fileName = path.split('/').last;
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]*$'), '');
    return nameWithoutExt
        .replaceAll(RegExp(r'[_-]'), ' ')
        .split(' ')
        .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _processContent(String content, String path) {
    final lowerPath = path.toLowerCase();

    if (lowerPath.endsWith('.md') || lowerPath.endsWith('.mdx')) {
      // Process markdown: remove frontmatter, clean up
      return _cleanMarkdown(content);
    } else if (lowerPath.endsWith('.html') || lowerPath.endsWith('.htm')) {
      // Process HTML: extract text content
      return _extractTextFromHtml(content);
    } else {
      // Other text files: return as-is with some cleanup
      return content.replaceAll(RegExp(r'\r\n'), '\n').trim();
    }
  }

  String _cleanMarkdown(String content) {
    // Remove frontmatter
    content = content.replaceAll(RegExp(r'^---[\s\S]*?---\n*'), '');

    // Remove HTML comments
    content = content.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    // Clean up excessive whitespace
    content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return content.trim();
  }

  String _extractTextFromHtml(String content) {
    // Simple HTML to text conversion
    // In a real implementation, you'd use a proper HTML parser
    return content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _extractMarkdownHeadings(String content, String path) {
    if (!path.toLowerCase().endsWith('.md') && !path.toLowerCase().endsWith('.mdx')) {
      return [];
    }

    final headings = <String>[];
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('#')) {
        final heading = trimmedLine.replaceAll(RegExp(r'^#+\s*'), '').trim();
        if (heading.isNotEmpty) {
          headings.add(heading);
        }
      }
    }

    return headings;
  }

  void dispose() {
    _client.close();
  }
}