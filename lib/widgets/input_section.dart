import 'package:flutter/material.dart';
import 'package:scraper/models/scraping_job.dart';

class InputSection extends StatelessWidget {
  final TextEditingController sourceUrlsController;
  final TextEditingController basePathController;
  final TextEditingController allowedDomainsController;
  final TextEditingController githubTokenController;
  final SourceType sourceType;
  final GitHubScope githubScope;
  final int maxDepth;
  final int githubMaxFileMB;
  final bool enabled;
  final Function(SourceType) onSourceTypeChanged;
  final Function(GitHubScope) onGithubScopeChanged;
  final Function(int) onMaxDepthChanged;
  final Function(int) onGithubMaxFileMBChanged;

  const InputSection({
    super.key,
    required this.sourceUrlsController,
    required this.basePathController,
    required this.allowedDomainsController,
    required this.githubTokenController,
    required this.sourceType,
    required this.githubScope,
    required this.maxDepth,
    required this.githubMaxFileMB,
    required this.onSourceTypeChanged,
    required this.onGithubScopeChanged,
    required this.onMaxDepthChanged,
    required this.onGithubMaxFileMBChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Input Sources',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: sourceUrlsController,
              decoration: const InputDecoration(
                labelText: 'Source URLs',
                hintText: 'Enter URLs (one per line)',
                border: OutlineInputBorder(),
                helperText: 'Enter one URL per line',
              ),
              enabled: enabled,
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            Text(
              'Source Type',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Column(
              children: SourceType.values.map((type) {
                return RadioListTile<SourceType>(
                  title: Text(_getSourceTypeLabel(type)),
                  value: type,
                  groupValue: sourceType,
                  onChanged: enabled ? (value) => onSourceTypeChanged(value!) : null,
                  dense: true,
                );
              }).toList(),
            ),
            if (sourceType == SourceType.website) ...[
              const SizedBox(height: 16),
              TextField(
                controller: basePathController,
                decoration: const InputDecoration(
                  labelText: 'Base Path (optional)',
                  hintText: 'e.g., /docs/',
                  border: OutlineInputBorder(),
                  helperText: 'Limit crawling to this path',
                ),
                enabled: enabled,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Max Depth: $maxDepth',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Slider(
                      value: maxDepth.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      onChanged: enabled ? (value) => onMaxDepthChanged(value.round()) : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: allowedDomainsController,
                decoration: const InputDecoration(
                  labelText: 'Allowed Domains',
                  hintText: 'example.com\napi.example.com',
                  border: OutlineInputBorder(),
                  helperText: 'Additional domains to allow (one per line)',
                ),
                enabled: enabled,
                maxLines: 3,
              ),
            ],
            if (sourceType == SourceType.github) ...[
              const SizedBox(height: 16),
              Text(
                'Repository Scope',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Column(
                children: GitHubScope.values.map((scope) {
                  return RadioListTile<GitHubScope>(
                    title: Text(_getGitHubScopeLabel(scope)),
                    subtitle: Text(_getGitHubScopeDescription(scope)),
                    value: scope,
                    groupValue: githubScope,
                    onChanged: enabled ? (value) => onGithubScopeChanged(value!) : null,
                    dense: true,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: githubMaxFileMB.toString()),
                      decoration: const InputDecoration(
                        labelText: 'Max file size (MB)',
                        hintText: 'Default 1',
                        helperText: 'Files larger than this are skipped',
                        border: OutlineInputBorder(),
                      ),
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        if (!enabled) return;
                        final mb = int.tryParse(value);
                        if (mb != null && mb > 0) {
                          onGithubMaxFileMBChanged(mb);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: githubTokenController,
                      decoration: const InputDecoration(
                        labelText: 'GitHub Token (optional)',
                        hintText: 'ghp_... or fine-grained token',
                        border: OutlineInputBorder(),
                        helperText: 'Used to increase rate limits and access private repos (not saved)',
                      ),
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      enabled: enabled,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getSourceTypeLabel(SourceType type) {
    switch (type) {
      case SourceType.website:
        return 'Website';
      case SourceType.github:
        return 'GitHub Repository';
    }
  }

  String _getGitHubScopeLabel(GitHubScope scope) {
    switch (scope) {
      case GitHubScope.fullRepo:
        return 'Full Repository';
      case GitHubScope.docsOnly:
        return 'Documentation Only';
    }
  }

  String _getGitHubScopeDescription(GitHubScope scope) {
    switch (scope) {
      case GitHubScope.fullRepo:
        return 'Include all files in the repository';
      case GitHubScope.docsOnly:
        return 'Only include docs/, *.md, *.mdx files';
    }
  }
}