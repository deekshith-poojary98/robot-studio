import 'package:flutter/material.dart';

import '../../core/gateway/models/package_info.dart';
import '../../core/theme/app_theme.dart';

Future<PackageInstallSelection?> showSearchPackagesDialog(
  BuildContext context, {
  required Future<List<PackageSearchResult>> Function(String query) onSearch,
  required Future<PackageVersionList> Function(String name) onLoadVersions,
}) {
  return showDialog<PackageInstallSelection>(
    context: context,
    builder: (context) => SearchPackagesDialog(
      onSearch: onSearch,
      onLoadVersions: onLoadVersions,
    ),
  );
}

class SearchPackagesDialog extends StatefulWidget {
  const SearchPackagesDialog({
    super.key,
    required this.onSearch,
    required this.onLoadVersions,
  });

  final Future<List<PackageSearchResult>> Function(String query) onSearch;
  final Future<PackageVersionList> Function(String name) onLoadVersions;

  @override
  State<SearchPackagesDialog> createState() => _SearchPackagesDialogState();
}

class _SearchPackagesDialogState extends State<SearchPackagesDialog> {
  final _queryController = TextEditingController();
  List<PackageSearchResult> _results = const [];
  bool _loading = false;
  String? _error;

  PackageSearchResult? _pending;
  List<String> _versions = const [];
  String? _selectedVersion;
  bool _loadingVersions = false;

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
      _pending = null;
      _versions = const [];
      _selectedVersion = null;
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

  Future<void> _selectForInstall(PackageSearchResult item) async {
    setState(() {
      _pending = item;
      _loadingVersions = true;
      _versions = const [];
      _selectedVersion = item.latestVersion.isNotEmpty
          ? item.latestVersion
          : null;
      _error = null;
    });
    try {
      final listed = await widget.onLoadVersions(item.name);
      if (!mounted) return;
      final versions = listed.versions.isNotEmpty
          ? listed.versions
          : [
              if (item.latestVersion.isNotEmpty) item.latestVersion,
            ];
      final latest = listed.latestVersion?.isNotEmpty == true
          ? listed.latestVersion!
          : (item.latestVersion.isNotEmpty
              ? item.latestVersion
              : (versions.isNotEmpty ? versions.first : null));
      setState(() {
        _versions = versions;
        _selectedVersion = latest;
        _loadingVersions = false;
        if (versions.isEmpty) {
          _error = 'No versions available for ${item.name}';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingVersions = false;
        // Fall back to search metadata latest version.
        if (item.latestVersion.isNotEmpty) {
          _versions = [item.latestVersion];
          _selectedVersion = item.latestVersion;
        } else {
          _error = 'Could not load versions: $error';
        }
      });
    }
  }

  void _confirmInstall() {
    final pending = _pending;
    final version = _selectedVersion?.trim();
    if (pending == null || version == null || version.isEmpty) {
      setState(() => _error = 'Select a package version to install');
      return;
    }
    Navigator.of(context).pop(
      PackageInstallSelection(
        name: pending.name,
        version: version,
        summary: pending.summary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search PyPI'),
      content: SizedBox(
        width: 560,
        height: 480,
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
                            final selected = _pending?.name == item.name;
                            return ListTile(
                              selected: selected,
                              title: Text(item.name),
                              subtitle: Text(
                                [
                                  if (item.latestVersion.isNotEmpty)
                                    'latest ${item.latestVersion}',
                                  if (item.summary != null) item.summary!,
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: FilledButton(
                                onPressed: _loadingVersions
                                    ? null
                                    : () => _selectForInstall(item),
                                child: Text(selected ? 'Selected' : 'Select'),
                              ),
                            );
                          },
                        ),
            ),
            if (_pending != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Install ${_pending!.name}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_loadingVersions)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedVersion != null &&
                                _versions.contains(_selectedVersion)
                            ? _selectedVersion
                            : (_versions.isNotEmpty ? _versions.first : null),
                        isExpanded: true,
                        menuMaxHeight: 180,
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        decoration: const InputDecoration(
                          labelText: 'Version',
                          helperText: 'Latest version is selected by default',
                        ),
                        items: [
                          for (var i = 0; i < _versions.length; i++)
                            DropdownMenuItem<String>(
                              value: _versions[i],
                              child: Text(
                                i == 0
                                    ? '${_versions[i]} (latest)'
                                    : _versions[i],
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedVersion = value;
                            _error = null;
                          });
                        },
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _pending = null;
                              _versions = const [];
                              _selectedVersion = null;
                            });
                          },
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _loadingVersions ? null : _confirmInstall,
                          child: const Text('Install'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
