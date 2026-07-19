import 'package:flutter/material.dart';

import '../../core/gateway/models/package_info.dart';
import '../../core/theme/app_theme.dart';

Future<PackageSearchResult?> showSearchPackagesDialog(
  BuildContext context, {
  required Future<List<PackageSearchResult>> Function(String query) onSearch,
}) {
  return showDialog<PackageSearchResult>(
    context: context,
    builder: (context) => SearchPackagesDialog(onSearch: onSearch),
  );
}

class SearchPackagesDialog extends StatefulWidget {
  const SearchPackagesDialog({
    super.key,
    required this.onSearch,
  });

  final Future<List<PackageSearchResult>> Function(String query) onSearch;

  @override
  State<SearchPackagesDialog> createState() => _SearchPackagesDialogState();
}

class _SearchPackagesDialogState extends State<SearchPackagesDialog> {
  final _queryController = TextEditingController();
  List<PackageSearchResult> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Enter a package name to search');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.onSearch(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search PyPI'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Package name',
                      hintText: 'robotframework-browser',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  child: const Text('Search'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            'Search PyPI for packages to install.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            return ListTile(
                              title: Text(item.name),
                              subtitle: Text(
                                [
                                  if (item.latestVersion.isNotEmpty)
                                    'v${item.latestVersion}',
                                  if (item.summary != null) item.summary!,
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(item),
                                child: const Text('Install'),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
