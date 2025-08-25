import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

class RagEntry {
  final String id;
  final String sourceUrl;
  final String? repo;
  final String? path;
  final String title;
  final List<String> headings;
  final String content;
  final int chunkIndex;
  final int chunkCount;
  final DateTime retrievedAt;
  final String hash;

  RagEntry({
    String? id,
    required this.sourceUrl,
    this.repo,
    this.path,
    required this.title,
    required this.headings,
    required this.content,
    required this.chunkIndex,
    required this.chunkCount,
    DateTime? retrievedAt,
    String? hash,
  })  : id = id ?? const Uuid().v4(),
        retrievedAt = retrievedAt ?? DateTime.now(),
        hash = hash ?? _generateHash(content);

  static String _generateHash(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source_url': sourceUrl,
        'repo': repo,
        'path': path,
        'title': title,
        'headings': headings,
        'content': content,
        'chunk_index': chunkIndex,
        'chunk_count': chunkCount,
        'retrieved_at': retrievedAt.toIso8601String(),
        'hash': hash,
      };

  String toJsonLine() => jsonEncode(toJson());

  static RagEntry fromJson(Map<String, dynamic> json) => RagEntry(
        id: json['id'],
        sourceUrl: json['source_url'],
        repo: json['repo'],
        path: json['path'],
        title: json['title'],
        headings: List<String>.from(json['headings']),
        content: json['content'],
        chunkIndex: json['chunk_index'],
        chunkCount: json['chunk_count'],
        retrievedAt: DateTime.parse(json['retrieved_at']),
        hash: json['hash'],
      );

  static RagEntry fromJsonLine(String jsonLine) {
    final json = jsonDecode(jsonLine) as Map<String, dynamic>;
    return fromJson(json);
  }
}

class ProcessedPage {
  final String url;
  final String title;
  final String content;
  final List<String> headings;
  final DateTime processedAt;
  final String? errorMessage;

  ProcessedPage({
    required this.url,
    required this.title,
    required this.content,
    required this.headings,
    DateTime? processedAt,
    this.errorMessage,
  }) : processedAt = processedAt ?? DateTime.now();

  bool get isSuccess => errorMessage == null;

  factory ProcessedPage.fromJson(Map<String, dynamic> json) => ProcessedPage(
        url: json['url'] as String,
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        headings: (json['headings'] as List?)?.cast<String>() ?? const [],
        processedAt: json['processedAt'] != null
            ? DateTime.parse(json['processedAt'] as String)
            : null,
        errorMessage: json['errorMessage'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'content': content,
        'headings': headings,
        'processedAt': processedAt.toIso8601String(),
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  List<RagEntry> toChunks({
    required int chunkSize,
    required int chunkOverlap,
    String? repo,
    String? path,
  }) {
    final chunks = _chunkText(content, chunkSize, chunkOverlap);
    return chunks
        .asMap()
        .entries
        .map((entry) => RagEntry(
              sourceUrl: url,
              repo: repo,
              path: path,
              title: title,
              headings: headings,
              content: entry.value,
              chunkIndex: entry.key,
              chunkCount: chunks.length,
            ))
        .toList();
  }

  List<String> _chunkText(String text, int chunkSize, int overlap) {
    if (text.length <= chunkSize) return [text];

    final chunks = <String>[];
    int start = 0;

    while (start < text.length) {
      int end = start + chunkSize;
      if (end >= text.length) {
        chunks.add(text.substring(start));
        break;
      }

      // Try to break at sentence or paragraph boundary
      int breakPoint = _findBreakPoint(text, start, end);
      chunks.add(text.substring(start, breakPoint));

      start = breakPoint - overlap;
      if (start < 0) start = 0;
    }

    return chunks;
  }

  int _findBreakPoint(String text, int start, int end) {
    // Look for paragraph break first
    int lastParagraph = text.lastIndexOf('\n\n', end - 1);
    if (lastParagraph > start) return lastParagraph;

    // Look for sentence break
    int lastSentence = text.lastIndexOf('.', end - 1);
    if (lastSentence > start && lastSentence < text.length - 1) {
      return lastSentence + 1;
    }

    // Look for word boundary
    int lastSpace = text.lastIndexOf(' ', end - 1);
    if (lastSpace > start) return lastSpace;

    return end;
  }
}