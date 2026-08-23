import '../../core/gateway/models/library_info.dart';

enum LibraryExplorerLevel { libraries, keywords, detail }

/// Owns library explorer state and filtering (widgets stay presentation-only).
class LibraryExplorerController {
  LibraryExplorerController({
    required this.listLibraries,
    required this.getLibrary,
  });

  final Future<List<LibraryInfo>> Function() listLibraries;
  final Future<LibraryInfo?> Function(String name) getLibrary;

  LibraryExplorerLevel level = LibraryExplorerLevel.libraries;
  List<LibraryInfo> libraries = [];
  LibraryInfo? selectedLibrary;
  LibraryKeywordInfo? selectedKeyword;
  String keywordFilter = '';
  bool loading = false;
  bool loadingDetail = false;
  String? error;

  List<LibraryKeywordInfo> get filteredKeywords {
    final all = selectedLibrary?.keywords ?? const <LibraryKeywordInfo>[];
    final needle = keywordFilter.trim().toLowerCase();
    if (needle.isEmpty) return all;
    // Name only — matching documentation made "commen" return dozens of
    // unrelated keywords whose docs happen to mention "comment".
    return [
      for (final kw in all)
        if (kw.name.toLowerCase().contains(needle)) kw,
    ];
  }

  Future<void> loadLibraries() async {
    loading = true;
    error = null;
    try {
      final items = await listLibraries();
      final seen = <String>{};
      libraries =
          [
            for (final item in items)
              if (seen.add(item.name.toLowerCase())) item,
          ]..sort((a, b) {
            if (a.builtin != b.builtin) return a.builtin ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
      level = LibraryExplorerLevel.libraries;
      selectedLibrary = null;
      selectedKeyword = null;
      keywordFilter = '';
    } catch (e) {
      error = '$e';
      libraries = [];
    } finally {
      loading = false;
    }
  }

  Future<void> openLibrary(LibraryInfo summary) async {
    loadingDetail = true;
    error = null;
    try {
      final detail = await getLibrary(summary.name);
      selectedLibrary = detail ?? summary;
      selectedKeyword = null;
      keywordFilter = '';
      level = LibraryExplorerLevel.keywords;
      if (detail == null ||
          (detail.keywords.isEmpty &&
              detail.keywordCount == 0 &&
              !detail.builtin)) {
        error =
            "'${summary.name}' is imported in this project but is not installed "
            'in the active environment.';
      }
      // Refresh summary count in list if we got a full load.
      if (detail != null && detail.keywordCount > 0) {
        final idx = libraries.indexWhere(
          (item) => item.name.toLowerCase() == detail.name.toLowerCase(),
        );
        if (idx >= 0) {
          libraries = [
            ...libraries.sublist(0, idx),
            LibraryInfo(
              name: detail.name,
              version: detail.version,
              documentation: detail.documentation,
              sourceType: detail.sourceType,
              sourcePath: detail.sourcePath,
              builtin: detail.builtin,
              keywordCount: detail.keywordCount,
              lastUpdated: detail.lastUpdated,
            ),
            ...libraries.sublist(idx + 1),
          ];
        }
      }
    } catch (e) {
      error = '$e';
    } finally {
      loadingDetail = false;
    }
  }

  void setKeywordFilter(String value) {
    keywordFilter = value;
  }

  void openKeyword(LibraryKeywordInfo keyword) {
    selectedKeyword = keyword;
    level = LibraryExplorerLevel.detail;
  }

  void back() {
    if (level == LibraryExplorerLevel.detail) {
      selectedKeyword = null;
      level = LibraryExplorerLevel.keywords;
      return;
    }
    if (level == LibraryExplorerLevel.keywords) {
      selectedLibrary = null;
      selectedKeyword = null;
      keywordFilter = '';
      level = LibraryExplorerLevel.libraries;
    }
  }
}
