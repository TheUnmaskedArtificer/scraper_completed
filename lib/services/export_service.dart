import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import 'package:scraper/models/scraping_job.dart';
import 'package:scraper/models/rag_entry.dart';

class ExportService {
  Future<void> generateExports(ScrapingJob job, List<ProcessedPage> pages) async {
    final exports = <String, Uint8List>{};

    // Generate RAG JSONL if requested
    if (job.outputConfig.format == OutputFormat.ragJsonl ||
        job.outputConfig.format == OutputFormat.both) {
      final jsonlContent = await _generateRagJsonl(job, pages);
      exports['rag_export.jsonl'] = Uint8List.fromList(utf8.encode(jsonlContent));
    }

    // Generate readable Markdown if requested
    if (job.outputConfig.format == OutputFormat.readableMarkdown ||
        job.outputConfig.format == OutputFormat.both) {
      final markdownFiles = await _generateReadableMarkdown(job, pages);
      exports.addAll(markdownFiles);
    }

    // Generate readable HTML if requested
    if (job.outputConfig.format == OutputFormat.readableHtml ||
        job.outputConfig.format == OutputFormat.both) {
      final htmlFiles = await _generateReadableHtml(job, pages);
      exports.addAll(htmlFiles);
    }

    // Store exports for later download
    await _storeExports(job.id, exports);
  }

  Future<String> _generateRagJsonl(ScrapingJob job, List<ProcessedPage> pages) async {
    final jsonlLines = <String>[];

    for (final page in pages) {
      if (page.isSuccess) {
        String? repo;
        String? path;

        // Extract repo info for GitHub sources
        if (job.sourceType == SourceType.github) {
          final urlParts = page.url.split('/');
          if (urlParts.length >= 5 && urlParts[2] == 'github.com') {
            repo = '${urlParts[3]}/${urlParts[4]}';
            if (urlParts.length > 7) {
              path = urlParts.skip(7).join('/');
            }
          }
        }

        final chunks = page.toChunks(
          chunkSize: job.outputConfig.chunkSize,
          chunkOverlap: job.outputConfig.chunkOverlap,
          repo: repo,
          path: path,
        );

        for (final chunk in chunks) {
          jsonlLines.add(chunk.toJsonLine());
        }
      }
    }

    return jsonlLines.join('\n');
  }

  Future<Map<String, Uint8List>> _generateReadableMarkdown(ScrapingJob job, List<ProcessedPage> pages) async {
    final files = <String, Uint8List>{};

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page.isSuccess) {
        String archivePath;
        if (job.sourceType == SourceType.github) {
          final info = _parseGitHubBlobUrl(page.url);
          if (info != null) {
            final repo = info['repo']!;
            final relPath = info['path']!;
            final mdPath = relPath.toLowerCase().endsWith('.md') || relPath.toLowerCase().endsWith('.mdx')
                ? relPath
                : '$relPath.md';
            archivePath = _sanitizePathForArchive('readable-md/$repo/$mdPath');
          } else {
            archivePath = _sanitizePathForArchive('readable-md/${_extractFileName(page.url)}.md');
          }
        } else {
          archivePath = _sanitizePathForArchive('readable-md/${_extractFileName(page.url)}.md');
        }
        final content = _formatAsMarkdown(page);
        files[archivePath] = Uint8List.fromList(utf8.encode(content));
      }
    }

    return files;
  }

  Future<Map<String, Uint8List>> _generateReadableHtml(ScrapingJob job, List<ProcessedPage> pages) async {
    final files = <String, Uint8List>{};

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page.isSuccess) {
        String archivePath;
        if (job.sourceType == SourceType.github) {
          final info = _parseGitHubBlobUrl(page.url);
          if (info != null) {
            final repo = info['repo']!;
            final relPath = info['path']!;
            final htmlPath = relPath.toLowerCase().endsWith('.html') || relPath.toLowerCase().endsWith('.htm')
                ? relPath
                : '$relPath.html';
            archivePath = _sanitizePathForArchive('readable-html/$repo/$htmlPath');
          } else {
            archivePath = _sanitizePathForArchive('readable-html/${_extractFileName(page.url)}.html');
          }
        } else {
          archivePath = _sanitizePathForArchive('readable-html/${_extractFileName(page.url)}.html');
        }
        final content = _formatAsHtml(page);
        files[archivePath] = Uint8List.fromList(utf8.encode(content));
      }
    }

    return files;
  }

  String _formatAsMarkdown(ProcessedPage page) {
    final buffer = StringBuffer();

    buffer.writeln('# ${page.title}');
    buffer.writeln();
    buffer.writeln('**Source:** ${page.url}');
    buffer.writeln('**Processed:** ${page.processedAt.toIso8601String()}');
    buffer.writeln();

    if (page.headings.isNotEmpty) {
      buffer.writeln('## Headings');
      for (final heading in page.headings) {
        buffer.writeln('- $heading');
      }
      buffer.writeln();
    }

    buffer.writeln('## Content');
    buffer.writeln();
    buffer.writeln(page.content);

    return buffer.toString();
  }

  String _formatAsHtml(ProcessedPage page) {
    final escapedTitle = _escapeHtml(page.title);
    final escapedContent = _escapeHtml(page.content);
    final escapedUrl = _escapeHtml(page.url);

    final headingsSection = page.headings.isNotEmpty
        ? '<div class="headings"><h2>Headings</h2><ul>' +
            page.headings.map((h) => '<li>${_escapeHtml(h)}</li>').join('') +
            '</ul></div>'
        : '';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$escapedTitle</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      max-width: 800px;
      margin: 0 auto;
      padding: 2rem;
      line-height: 1.6;
    }
    .meta {
      background: #f5f5f5;
      padding: 1rem;
      border-radius: 8px;
      margin-bottom: 2rem;
    }
    .headings {
      background: #e3f2fd;
      padding: 1rem;
      border-radius: 8px;
      margin-bottom: 2rem;
    }
    .content {
      white-space: pre-wrap;
    }
  </style>
</head>
<body>
  <h1>$escapedTitle</h1>

  <div class="meta">
    <strong>Source:</strong> <a href="$escapedUrl">$escapedUrl</a><br>
    <strong>Processed:</strong> ${page.processedAt.toIso8601String()}
  </div>

  $headingsSection

  <h2>Content</h2>
  <div class="content">$escapedContent</div>
</body>
</html>''';
  }

  String _escapeHtml(String text) {
    // Escape minimal HTML entities
    return text
        .replaceAll('&', '&')
        .replaceAll('<', '<')
        .replaceAll('>', '>')
        .replaceAll('"', '"')
        .replaceAll("'", ''');
  }

  String _extractFileName(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;

    if (segments.isNotEmpty) {
      final lastSegment = segments.last;
      if (lastSegment.isNotEmpty && !lastSegment.endsWith('/')) {
        return lastSegment;
      }
    }

    return uri.host.replaceAll('.', '_');
  }

  String _sanitizeFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Map<String, String>? _parseGitHubBlobUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host != 'github.com') return null;
      // Expected: /owner/repo/blob/branch/path/to/file
      final segs = uri.pathSegments;
      if (segs.length < 5) return null;
      if (segs[2] != 'blob') return null;
      final owner = segs[0];
      final repo = segs[1];
      final branch = segs[3];
      final path = segs.skip(4).join('/');
      if (owner.isEmpty || repo.isEmpty || path.isEmpty) return null;
      return {
        'repo': '$owner/$repo',
        'path': path,
        'branch': branch,
      };
    } catch (_) {
      return null;
    }
  }

  String _sanitizePathForArchive(String path) {
    // Keep forward slashes for folders; sanitize other characters
    final cleaned = path
        .replaceAll(RegExp(r'\\+'), '/')
        .replaceAll(RegExp(r'[^a-zA-Z0-9._/\-]'), '_')
        .replaceAll(RegExp(r'/+'), '/')
        .replaceAll(RegExp(r'^/+'), '');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  Future<void> _storeExports(String jobId, Map<String, Uint8List> exports) async {
    _exportCache[jobId] = exports;
  }

  static final Map<String, Map<String, Uint8List>> _exportCache = {};

  Future<void> downloadResults(ScrapingJob job) async {
    final exports = _exportCache[job.id];
    if (exports == null || exports.isEmpty) {
      throw Exception('No exports found for job ${job.id}');
    }

    // Create ZIP file
    final archive = Archive();
    for (final entry in exports.entries) {
      final file = ArchiveFile(entry.key, entry.value.length, entry.value);
      archive.addFile(file);
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('Failed to create ZIP file');
    }

    // Save via FileSaver (works on web/desktop/mobile)
    await FileSaver.instance.saveFile(
      name: 'scrape_${job.id.substring(0,8)}.zip',
      bytes: zipData,
      ext: 'zip',
      mimeType: MimeType.other,
    );
  }
}