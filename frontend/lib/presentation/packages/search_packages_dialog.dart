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

  /// Keeps the results list from stretching the dialog on a long response.
  static const _resultsMaxHeight = 236.0;
  static const _resultsPlaceholderHeight = 96.0;

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
          : [if (item.latestVersion.isNotEmpty) item.latestVersion];
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

  bool get _canInstall =>
      _pending != null &&
      !_loadingVersions &&
      (_selectedVersion?.trim().isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Text('Search PyPI', style: theme.textTheme.titleLarge),
      content: SizedBox(
        width: AppDialogWidth.wide,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Package name',
                      hintText: 'robotframework-browser',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  height: 36,
                  child: FilledButton(
                    onPressed: _loading ? null : _search,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Search'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: context.palette.error, fontSize: 11.5),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _resultsArea(context),
            if (_pending != null) _versionPicker(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _canInstall ? _confirmInstall : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(76, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Install'),
        ),
      ],
    );
  }

  Widget _resultsArea(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: _resultsPlaceholderHeight,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return SizedBox(
        height: _resultsPlaceholderHeight,
        child: Center(
          child: Text(
            'Search PyPI for packages to install.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _resultsMaxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: context.palette.borderSubtle),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _results.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              thickness: 1,
              color: context.palette.borderSubtle,
            ),
            itemBuilder: (context, index) {
              final item = _results[index];
              return _ResultRow(
                item: item,
                selected: _pending?.name == item.name,
                onTap: _loadingVersions ? null : () => _selectForInstall(item),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _versionPicker(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: _loadingVersions
          ? const SizedBox(
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value:
                  _selectedVersion != null &&
                      _versions.contains(_selectedVersion)
                  ? _selectedVersion
                  : (_versions.isNotEmpty ? _versions.first : null),
              isExpanded: true,
              isDense: true,
              menuMaxHeight: 220,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              style: TextStyle(
                fontSize: 12.5,
                color: context.palette.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Version',
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.sm,
                    right: AppSpacing.xs,
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 14,
                    color: context.palette.textMuted,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 26,
                  minHeight: 26,
                ),
              ),
              items: [
                for (var i = 0; i < _versions.length; i++)
                  DropdownMenuItem<String>(
                    value: _versions[i],
                    child: Text(
                      i == 0 ? '${_versions[i]} (latest)' : _versions[i],
                      style: const TextStyle(fontSize: 12.5),
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
    );
  }
}

/// One PyPI hit. Tapping the row picks it — a teal button per row put accent on
/// every result instead of on the single Install action.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PackageSearchResult item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (item.latestVersion.isNotEmpty) 'latest ${item.latestVersion}',
      if (item.summary != null && item.summary!.trim().isNotEmpty)
        item.summary!.trim(),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      hoverColor: context.palette.surfaceHover,
      child: Container(
        color: selected ? context.palette.accentSoft : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.check_circle, size: 15, color: context.palette.accent),
            ],
          ],
        ),
      ),
    );
  }
}
