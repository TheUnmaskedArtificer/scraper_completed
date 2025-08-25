import 'package:flutter/material.dart';

class CrawlerControls extends StatelessWidget {
  final int maxPages;
  final int concurrency;
  final int delayMs;
  final bool followSitemaps;
  final TextEditingController userAgentController;
  final Function(int) onMaxPagesChanged;
  final Function(int) onConcurrencyChanged;
  final Function(int) onDelayChanged;
  final Function(bool) onFollowSitemapsChanged;

  const CrawlerControls({
    super.key,
    required this.maxPages,
    required this.concurrency,
    required this.delayMs,
    required this.followSitemaps,
    required this.userAgentController,
    required this.onMaxPagesChanged,
    required this.onConcurrencyChanged,
    required this.onDelayChanged,
    required this.onFollowSitemapsChanged,
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
              'Crawler Controls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Max Pages',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: maxPages.toString()),
                    onChanged: (value) {
                      final pages = int.tryParse(value);
                      if (pages != null && pages > 0) {
                        onMaxPagesChanged(pages);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Concurrency',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: concurrency.toString()),
                    onChanged: (value) {
                      final conc = int.tryParse(value);
                      if (conc != null && conc > 0 && conc <= 10) {
                        onConcurrencyChanged(conc);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Delay (ms)',
                border: OutlineInputBorder(),
                helperText: 'Delay between requests to be respectful',
              ),
              keyboardType: TextInputType.number,
              controller: TextEditingController(text: delayMs.toString()),
              onChanged: (value) {
                final delay = int.tryParse(value);
                if (delay != null && delay >= 0) {
                  onDelayChanged(delay);
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: true,
                  onChanged: null, // Always enabled
                ),
                const Text('Respect robots.txt'),
                const Spacer(),
                const Icon(
                  Icons.lock,
                  size: 16,
                  color: Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: followSitemaps,
                  onChanged: (bool? value) => onFollowSitemapsChanged(value ?? false),
                ),
                const Text('Follow sitemaps'),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: userAgentController,
              decoration: const InputDecoration(
                labelText: 'User-Agent',
                border: OutlineInputBorder(),
                helperText: 'Identify your crawler to website owners',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rate Limiting & Ethics',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This scraper automatically respects robots.txt, implements rate limiting, and includes retry logic with backoff for 429/5xx responses.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}