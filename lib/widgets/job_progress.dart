import 'package:flutter/material.dart';
import 'package:scraper/models/scraping_job.dart';

class JobProgress extends StatelessWidget {
  final ScrapingJob job;

  const JobProgress({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(job.status),
                  color: _getStatusColor(job.status, context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Job Status: ${_getStatusText(job.status)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  'ID: ${job.id.substring(0, 8)}...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            if (job.status == JobStatus.running || job.status == JobStatus.completed) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: job.progress,
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Progress: ${(job.progress * 100).toStringAsFixed(1)}%'),
                  Text('${job.processedPages}/${job.totalPages} pages'),
                ],
              ),
              if (job.failedPages > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Failed: ${job.failedPages} pages',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
            if (job.errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        job.errorMessage ?? 'Unknown error',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildInfoChip('Source Type', job.sourceType.name, context),
                _buildInfoChip('Output Format', job.outputConfig.format.name, context),
                if (job.websiteConfig != null)
                  _buildInfoChip('Max Depth', job.websiteConfig?.maxDepth.toString() ?? 'N/A', context),
                if (job.githubConfig != null)
                  _buildInfoChip('GitHub Scope', job.githubConfig?.scope.name ?? 'N/A', context),
                _buildInfoChip('Max Pages', job.crawlerConfig.maxPages.toString(), context),
                _buildInfoChip('URLs', job.sourceUrls.length.toString(), context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  IconData _getStatusIcon(JobStatus status) {
    switch (status) {
      case JobStatus.pending:
        return Icons.schedule;
      case JobStatus.running:
        return Icons.play_arrow;
      case JobStatus.completed:
        return Icons.check_circle;
      case JobStatus.failed:
        return Icons.error;
    }
  }

  Color _getStatusColor(JobStatus status, BuildContext context) {
    switch (status) {
      case JobStatus.pending:
        return Theme.of(context).colorScheme.secondary;
      case JobStatus.running:
        return Theme.of(context).colorScheme.primary;
      case JobStatus.completed:
        return Theme.of(context).colorScheme.tertiary;
      case JobStatus.failed:
        return Theme.of(context).colorScheme.error;
    }
  }

  String _getStatusText(JobStatus status) {
    switch (status) {
      case JobStatus.pending:
        return 'Pending';
      case JobStatus.running:
        return 'Running';
      case JobStatus.completed:
        return 'Completed';
      case JobStatus.failed:
        return 'Failed';
    }
  }
}
