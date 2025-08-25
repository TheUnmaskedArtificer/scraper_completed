import 'package:uuid/uuid.dart';

enum SourceType { website, github }

enum OutputFormat { ragJsonl, readableMarkdown, readableHtml, both }

enum GitHubScope { fullRepo, docsOnly }

enum JobStatus { pending, running, completed, failed }

class ScrapingJob {
  final String id;
  final List<String> sourceUrls;
  final SourceType sourceType;
  final WebsiteConfig? websiteConfig;
  final GitHubConfig? githubConfig;
  final OutputConfig outputConfig;
  final CrawlerConfig crawlerConfig;
  final DateTime createdAt;
  JobStatus status;
  String? errorMessage;
  int totalPages;
  int processedPages;
  int failedPages;

  ScrapingJob({
    String? id,
    required this.sourceUrls,
    required this.sourceType,
    this.websiteConfig,
    this.githubConfig,
    required this.outputConfig,
    required this.crawlerConfig,
    DateTime? createdAt,
    this.status = JobStatus.pending,
    this.errorMessage,
    this.totalPages = 0,
    this.processedPages = 0,
    this.failedPages = 0,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  double get progress => totalPages > 0 ? processedPages / totalPages : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceUrls': sourceUrls,
        'sourceType': sourceType.name,
        'websiteConfig': websiteConfig?.toJson(),
        'githubConfig': githubConfig?.toJson(),
        'outputConfig': outputConfig.toJson(),
        'crawlerConfig': crawlerConfig.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'errorMessage': errorMessage,
        'totalPages': totalPages,
        'processedPages': processedPages,
        'failedPages': failedPages,
      };

  static ScrapingJob fromJson(Map<String, dynamic> json) => ScrapingJob(
        id: json['id'],
        sourceUrls: List<String>.from(json['sourceUrls']),
        sourceType: SourceType.values.firstWhere((e) => e.name == json['sourceType']),
        websiteConfig: json['websiteConfig'] != null ? WebsiteConfig.fromJson(json['websiteConfig']) : null,
        githubConfig: json['githubConfig'] != null ? GitHubConfig.fromJson(json['githubConfig']) : null,
        outputConfig: OutputConfig.fromJson(json['outputConfig']),
        crawlerConfig: CrawlerConfig.fromJson(json['crawlerConfig']),
        createdAt: DateTime.parse(json['createdAt']),
        status: JobStatus.values.firstWhere((e) => e.name == json['status']),
        errorMessage: json['errorMessage'],
        totalPages: json['totalPages'] ?? 0,
        processedPages: json['processedPages'] ?? 0,
        failedPages: json['failedPages'] ?? 0,
      );
}

class WebsiteConfig {
  final String? basePath;
  final int maxDepth;
  final List<String> allowedDomains;

  WebsiteConfig({
    this.basePath,
    required this.maxDepth,
    required this.allowedDomains,
  });

  Map<String, dynamic> toJson() => {
        'basePath': basePath,
        'maxDepth': maxDepth,
        'allowedDomains': allowedDomains,
      };

  static WebsiteConfig fromJson(Map<String, dynamic> json) => WebsiteConfig(
        basePath: json['basePath'],
        maxDepth: json['maxDepth'],
        allowedDomains: List<String>.from(json['allowedDomains']),
      );
}

class GitHubConfig {
  final GitHubScope scope;
  final String? authToken;
  final int? maxFileBytes; // configurable size cap (defaults handled in scraper)

  GitHubConfig({required this.scope, this.authToken, this.maxFileBytes});

  Map<String, dynamic> toJson() => {
        'scope': scope.name,
        'maxFileBytes': maxFileBytes,
      };

  static GitHubConfig fromJson(Map<String, dynamic> json) => GitHubConfig(
        scope: GitHubScope.values.firstWhere((e) => e.name == json['scope']),
        maxFileBytes: json['maxFileBytes'],
      );
}

class OutputConfig {
  final OutputFormat format;
  final int chunkSize;
  final int chunkOverlap;

  OutputConfig({
    required this.format,
    this.chunkSize = 800,
    this.chunkOverlap = 200,
  });

  Map<String, dynamic> toJson() => {
        'format': format.name,
        'chunkSize': chunkSize,
        'chunkOverlap': chunkOverlap,
      };

  static OutputConfig fromJson(Map<String, dynamic> json) => OutputConfig(
        format: OutputFormat.values.firstWhere((e) => e.name == json['format']),
        chunkSize: json['chunkSize'] ?? 800,
        chunkOverlap: json['chunkOverlap'] ?? 200,
      );
}

class CrawlerConfig {
  final int maxPages;
  final int concurrency;
  final int delayMs;
  final bool respectRobots;
  final bool followSitemaps;
  final String userAgent;

  CrawlerConfig({
    this.maxPages = 500,
    this.concurrency = 4,
    this.delayMs = 500,
    this.respectRobots = true,
    this.followSitemaps = true,
    this.userAgent = 'Mozilla/5.0 (compatible; WebScraperBot/1.0)',
  });

  Map<String, dynamic> toJson() => {
        'maxPages': maxPages,
        'concurrency': concurrency,
        'delayMs': delayMs,
        'respectRobots': respectRobots,
        'followSitemaps': followSitemaps,
        'userAgent': userAgent,
      };

  static CrawlerConfig fromJson(Map<String, dynamic> json) => CrawlerConfig(
        maxPages: json['maxPages'] ?? 500,
        concurrency: json['concurrency'] ?? 4,
        delayMs: json['delayMs'] ?? 500,
        respectRobots: json['respectRobots'] ?? true,
        followSitemaps: json['followSitemaps'] ?? true,
        userAgent: json['userAgent'] ?? 'Mozilla/5.0 (compatible; WebScraperBot/1.0)',
      );
}