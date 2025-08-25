import 'package:flutter/material.dart';
import 'package:scraper/models/scraping_job.dart';

class OutputSection extends StatelessWidget {
  final OutputFormat outputFormat;
  final int chunkSize;
  final int chunkOverlap;
  final Function(OutputFormat) onOutputFormatChanged;
  final Function(int) onChunkSizeChanged;
  final Function(int) onChunkOverlapChanged;
  final bool enabled;

  const OutputSection({
    super.key,
    required this.outputFormat,
    required this.chunkSize,
    required this.chunkOverlap,
    required this.onOutputFormatChanged,
    required this.onChunkSizeChanged,
    required this.onChunkOverlapChanged,
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
              'Output Configuration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Output Format',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Column(
              children: OutputFormat.values.map((format) {
                return RadioListTile<OutputFormat>(
                  title: Text(_getOutputFormatLabel(format)),
                  subtitle: Text(_getOutputFormatDescription(format)),
                  value: format,
                  groupValue: outputFormat,
                  onChanged: enabled ? (value) => onOutputFormatChanged(value!) : null,
                  dense: true,
                );
              }).toList(),
            ),
            if (_showChunkingControls(outputFormat)) ...[
              const SizedBox(height: 16),
              Text(
                'RAG Chunking Settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Chunk Size (characters)',
                        border: OutlineInputBorder(),
                      ),
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      controller: TextEditingController(text: chunkSize.toString()),
                      onChanged: (value) {
                        if (!enabled) return;
                        final size = int.tryParse(value);
                        if (size != null && size > 0) {
                          onChunkSizeChanged(size);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Chunk Overlap (characters)',
                        border: OutlineInputBorder(),
                      ),
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      controller: TextEditingController(text: chunkOverlap.toString()),
                      onChanged: (value) {
                        if (!enabled) return;
                        final overlap = int.tryParse(value);
                        if (overlap != null && overlap >= 0) {
                          onChunkOverlapChanged(overlap);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Chunking breaks content into overlapping character segments for RAG systems.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _showChunkingControls(OutputFormat format) {
    return format == OutputFormat.ragJsonl || format == OutputFormat.both;
  }

  String _getOutputFormatLabel(OutputFormat format) {
    switch (format) {
      case OutputFormat.ragJsonl:
        return 'RAG JSONL';
      case OutputFormat.readableMarkdown:
        return 'Readable Markdown';
      case OutputFormat.readableHtml:
        return 'Readable HTML';
      case OutputFormat.both:
        return 'Both RAG and Readable';
    }
  }

  String _getOutputFormatDescription(OutputFormat format) {
    switch (format) {
      case OutputFormat.ragJsonl:
        return 'Chunked JSONL format optimized for RAG systems';
      case OutputFormat.readableMarkdown:
        return 'Clean Markdown files for human reading';
      case OutputFormat.readableHtml:
        return 'Formatted HTML files with styling';
      case OutputFormat.both:
        return 'Generate both RAG JSONL and readable formats';
    }
  }
}