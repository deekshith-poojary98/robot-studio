import 'dart:async';

import '../../../core/gateway/transport_gateway.dart';
import '../../../core/logging/app_logger.dart';
import 'shell_controller.dart';

class EditorShellController {
  EditorShellController({
    required this.gateway,
    required this.notify,
    required this.isMounted,
    required this.workspace,
  });

  final TransportGateway gateway;
  final ShellNotify notify;
  final ShellMounted isMounted;
  final WorkspaceInfo? Function() workspace;

  List<EditorTabInfo> tabs = [];
  String? activePath;
  List<IndexedSymbolInfo> documentOutline = [];
  bool loadingOutline = false;
  bool wordWrap = true;
  String? statusMessage;
  int? jumpToLine;
  int? jumpToColumn;
  int cursorLine = 1;
  int cursorColumn = 1;
  List<FileTreeNode> fileTree = [];
  final Set<String> expandedDirs = {};
  final Map<String, List<FileTreeNode>> childrenByPath = {};
  final Set<String> loadingDirs = {};
  List<String> recentFiles = [];
  IndexedSymbolInfo? selectedOutlineSymbol;
  List<CompletionItemInfo> completionItems = [];
  List<DiagnosticInfo> diagnostics = [];
  List<DiagnosticInfo> workspaceProblems = [];
  SignatureHelpInfo? hoverTooltip;
  IndexedSymbolInfo? peekDefinition;
  bool loadingLanguageFeatures = false;
  bool loadingFileTree = false;

  Timer? languageDebounce;
  Timer? hoverDebounce;
  Timer? statusTimer;
  int _hoverRequestId = 0;

  static const statusMessageTtl = Duration(seconds: 4);

  /// Show a transient notice above the editor (Saved…, Copied path, …).
  ///
  /// The strip pushes editor content down, so it always expires — callers used
  /// to assign [statusMessage] directly and the notice stayed until the next
  /// file open. Set synchronously so an enclosing `setState` paints it at once;
  /// the clear notifies on its own.
  void setStatusMessage(String? message, {Duration ttl = statusMessageTtl}) {
    statusTimer?.cancel();
    statusTimer = null;
    statusMessage = message;
    if (message == null) return;
    statusTimer = Timer(ttl, () {
      statusTimer = null;
      statusMessage = null;
      if (isMounted()) notify();
    });
  }

  EditorTabInfo? get activeTab {
    final path = activePath;
    if (path == null) return null;
    for (final tab in tabs) {
      if (tab.path == path) return tab;
    }
    return null;
  }

  void dispose() {
    languageDebounce?.cancel();
    hoverDebounce?.cancel();
    statusTimer?.cancel();
  }

  void reset() {
    tabs = [];
    activePath = null;
    documentOutline = [];
    selectedOutlineSymbol = null;
    completionItems = [];
    diagnostics = [];
    workspaceProblems = [];
    hoverTooltip = null;
    peekDefinition = null;
    statusTimer?.cancel();
    statusTimer = null;
    statusMessage = null;
    jumpToLine = null;
    jumpToColumn = null;
    fileTree = [];
    expandedDirs.clear();
    childrenByPath.clear();
    loadingDirs.clear();
    loadingFileTree = false;
    recentFiles = [];
    languageDebounce?.cancel();
    hoverDebounce?.cancel();
  }

  void trackRecentFile(String path) {
    recentFiles = [
      path,
      ...recentFiles.where((item) => item != path),
    ].take(10).toList();
  }

  void onContentChanged(String path, String content) {
    final tabIndex = tabs.indexWhere((tab) => tab.path == path);
    if (tabIndex < 0) return;
    tabs[tabIndex].content = content;
    // Keep caret signature card; refreshLanguageFeatures updates or clears it.
    notify();
    scheduleLanguageRefresh();
  }

  void onCursorChanged(int line, int column) {
    cursorLine = line;
    cursorColumn = column;
    final tab = activeTab;
    if (tab != null) {
      tab.cursorLine = line;
      tab.cursorColumn = column;
    }
    notify();
    scheduleLanguageRefresh();
  }

  void scheduleLanguageRefresh() {
    languageDebounce?.cancel();
    languageDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(refreshLanguageFeatures());
    });
  }

  Future<void> refreshLanguageFeatures() async {
    final tab = activeTab;
    if (tab == null || workspace() == null) return;
    final isRobot =
        tab.path.endsWith('.robot') || tab.path.endsWith('.resource');
    if (!isRobot) {
      if (!isMounted()) return;
      completionItems = [];
      diagnostics = [];
      hoverTooltip = null;
      notify();
      return;
    }

    // Keep showing the current Problems list while refresh runs — never flash
    // a skeleton on every keystroke.
    try {
      final token =
          extractWordAtCursor(tab.content, cursorLine, cursorColumn) ?? '';
      final results = await Future.wait([
        gateway.languageCompletion(
          filePath: tab.path,
          line: cursorLine,
          column: cursorColumn,
          content: tab.content,
          query: token,
        ),
        gateway.languageDiagnostics(
          filePath: tab.path,
          content: tab.content,
        ),
        gateway.languageSignatureHelp(
          filePath: tab.path,
          line: cursorLine,
          column: cursorColumn,
          content: tab.content,
        ),
      ]);
      if (!isMounted()) return;
      completionItems = results[0] as List<CompletionItemInfo>;
      diagnostics = results[1] as List<DiagnosticInfo>;
      final signature = results[2] as SignatureHelpInfo?;
      // Caret-driven signature: update when resolved; clear when leaving a call.
      hoverTooltip = signature;
      // Update Problems for the active file in place (no full-workspace rescan).
      workspaceProblems = [
        ...workspaceProblems.where((item) => item.filePath != tab.path),
        ...diagnostics,
      ];
      loadingLanguageFeatures = false;
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loadingLanguageFeatures = false;
      notify();
      AppLogger.debug('Language refresh failed', tag: 'Shell', data: '$error');
    }
  }

  void recordCompletionUsage(CompletionItemInfo item) {
    unawaited(() async {
      try {
        await gateway.languageCompletionUsage(
          label: item.label,
          kind: item.kind,
        );
      } catch (error) {
        AppLogger.debug(
          'Completion usage record failed',
          tag: 'Shell',
          data: '$error',
        );
      }
    }());
  }

  void clearHoverTooltip() {
    hoverDebounce?.cancel();
    if (hoverTooltip == null) return;
    hoverTooltip = null;
    notify();
  }

  Future<void> requestHoverTooltip({
    required int line,
    required int column,
  }) async {
    final tab = activeTab;
    if (tab == null || workspace() == null) return;
    final isRobot =
        tab.path.endsWith('.robot') || tab.path.endsWith('.resource');
    if (!isRobot) {
      clearHoverTooltip();
      return;
    }

    final requestId = ++_hoverRequestId;
    try {
      final signature = await gateway.languageSignatureHelp(
        filePath: tab.path,
        line: line,
        column: column,
        content: tab.content,
      );
      if (!isMounted() || requestId != _hoverRequestId) return;
      if (signature != null) {
        hoverTooltip = signature;
        notify();
        return;
      }

      final token = extractRobotTokenAt(tab.content, line, column);
      if (token == null || token.isEmpty) {
        hoverTooltip = null;
        notify();
        return;
      }
      final hover = await gateway.languageHover(
        name: token,
        filePath: tab.path,
        line: line,
        column: column,
        content: tab.content,
      );
      if (!isMounted() || requestId != _hoverRequestId) return;
      if (hover == null) {
        hoverTooltip = null;
        notify();
        return;
      }
      hoverTooltip = SignatureHelpInfo(
        keyword: hover.name,
        documentation: hover.documentation,
        detail: hover.detail.isNotEmpty ? hover.detail : hover.kind.label,
        parameters: parametersFromDetail(hover.detail),
      );
      notify();
    } catch (error) {
      if (!isMounted() || requestId != _hoverRequestId) return;
      AppLogger.debug('Hover tooltip failed', tag: 'Shell', data: '$error');
      hoverTooltip = null;
      notify();
    }
  }

  Future<void> refreshWorkspaceProblems() async {
    final problems = <DiagnosticInfo>[];
    for (final tab in tabs) {
      if (!tab.path.endsWith('.robot') && !tab.path.endsWith('.resource')) {
        continue;
      }
      try {
        final tabDiagnostics = await gateway.languageDiagnostics(
          filePath: tab.path,
          content: tab.content,
        );
        problems.addAll(tabDiagnostics);
      } catch (_) {
        continue;
      }
    }
    if (!isMounted()) return;
    workspaceProblems = problems;
    notify();
  }

  Future<void> loadOutline(String path) async {
    loadingOutline = true;
    selectedOutlineSymbol = null;
    notify();
    try {
      documentOutline = await gateway.documentSymbols(path);
      if (!isMounted()) return;
      loadingOutline = false;
      notify();
    } catch (_) {
      if (!isMounted()) return;
      documentOutline = [];
      loadingOutline = false;
      notify();
    }
  }

  Future<void> loadFileTree() async {
    if (workspace() == null) {
      fileTree = [];
      expandedDirs.clear();
      childrenByPath.clear();
      loadingDirs.clear();
      notify();
      return;
    }
    loadingFileTree = true;
    notify();
    try {
      // Depth 0: immediate children only (VS Code lazy-expand model).
      fileTree = await gateway.listFileTree(depth: 0);
      expandedDirs.clear();
      childrenByPath.clear();
      loadingDirs.clear();
      if (!isMounted()) return;
      loadingFileTree = false;
      notify();
    } catch (_) {
      fileTree = [];
      loadingFileTree = false;
      notify();
    }
  }

  /// Incrementally refresh the parent of [path] without collapsing the tree.
  Future<void> refreshParentOf(String path) async {
    final ws = workspace();
    if (ws == null) return;
    final normalized = path.replaceAll('\\', '/');
    final wsPath = ws.path.replaceAll('\\', '/');
    String? parent;
    final slash = normalized.lastIndexOf('/');
    if (slash > 0) {
      parent = normalized.substring(0, slash);
    }
    await refreshDirectory(parent, workspaceRoot: wsPath);
  }

  Future<void> refreshDirectory(
    String? directoryPath, {
    required String workspaceRoot,
  }) async {
    final ws = workspace();
    if (ws == null) return;
    final isRoot = directoryPath == null ||
        directoryPath.isEmpty ||
        directoryPath.replaceAll('\\', '/') == workspaceRoot;

    try {
      if (isRoot) {
        final fresh = await gateway.listFileTree(depth: 0);
        if (!isMounted()) return;
        fileTree = fresh;
        _pruneMissingTreeState(fresh);
        notify();
        return;
      }

      final parent = directoryPath.replaceAll('\\', '/');
      // Only hit the API when the parent is visible (expanded or cached).
      if (!expandedDirs.contains(parent) && !childrenByPath.containsKey(parent)) {
        // Parent collapsed — mark hasChildren on ancestor if present in root.
        notify();
        return;
      }
      final kids = await gateway.listFileTree(path: parent, depth: 0);
      if (!isMounted()) return;
      childrenByPath[parent] = kids;
      _pruneMissingTreeState(fileTree);
      notify();
    } catch (_) {
      // Ignore transient FS races during delete/rename storms.
    }
  }

  void removePathFromTree(String path) {
    final normalized = path.replaceAll('\\', '/');
    fileTree = _filterNodes(fileTree, normalized);
    final updated = <String, List<FileTreeNode>>{};
    for (final entry in childrenByPath.entries) {
      if (entry.key == normalized || entry.key.startsWith('$normalized/')) {
        continue;
      }
      updated[entry.key] = _filterNodes(entry.value, normalized);
    }
    childrenByPath
      ..clear()
      ..addAll(updated);
    expandedDirs.removeWhere(
      (item) => item == normalized || item.startsWith('$normalized/'),
    );
    notify();
  }

  List<FileTreeNode> _filterNodes(List<FileTreeNode> nodes, String removed) {
    return nodes
        .where((node) {
          final p = node.path.replaceAll('\\', '/');
          return p != removed && !p.startsWith('$removed/');
        })
        .toList();
  }

  void _pruneMissingTreeState(List<FileTreeNode> roots) {
    final alive = <String>{};
    void walk(List<FileTreeNode> nodes) {
      for (final node in nodes) {
        alive.add(node.path.replaceAll('\\', '/'));
        final cached = childrenByPath[node.path];
        if (cached != null) walk(cached);
      }
    }

    walk(roots);
    for (final entry in childrenByPath.entries) {
      walk(entry.value);
    }
    expandedDirs.removeWhere((path) {
      final n = path.replaceAll('\\', '/');
      return !alive.contains(n);
    });
    childrenByPath.removeWhere((key, _) {
      final n = key.replaceAll('\\', '/');
      return !alive.contains(n);
    });
  }

  Future<void> toggleDirectory(String path) async {
    if (expandedDirs.contains(path)) {
      expandedDirs.remove(path);
      notify();
      return;
    }
    await ensureExpanded(path);
  }

  /// Expand [path] if collapsed, loading children when needed.
  Future<void> ensureExpanded(String path) async {
    if (expandedDirs.contains(path) && childrenByPath.containsKey(path)) {
      return;
    }
    expandedDirs.add(path);
    if (!childrenByPath.containsKey(path)) {
      loadingDirs.add(path);
      notify();
      try {
        final kids = await gateway.listFileTree(path: path, depth: 0);
        childrenByPath[path] = kids;
      } catch (_) {
        childrenByPath[path] = const [];
      } finally {
        loadingDirs.remove(path);
      }
    }
    if (!isMounted()) return;
    notify();
  }

  /// Collapse every expanded folder while keeping cached children for fast re-expand.
  void collapseAllFolders() {
    if (expandedDirs.isEmpty) return;
    expandedDirs.clear();
    notify();
  }

  List<FileTreeNode> childrenOf(FileTreeNode node) {
    if (childrenByPath.containsKey(node.path)) {
      return childrenByPath[node.path]!;
    }
    if (node.children.isNotEmpty) return node.children;
    return const [];
  }

  List<FlatFileTreeRow> visibleFileRows() {
    final rows = <FlatFileTreeRow>[];

    void walk(List<FileTreeNode> nodes, int depth) {
      for (final node in nodes) {
        final expanded = expandedDirs.contains(node.path);
        final loading = loadingDirs.contains(node.path);
        rows.add(
          FlatFileTreeRow(
            node: node,
            depth: depth,
            expanded: expanded,
            loading: loading,
          ),
        );
        if (node.isDir && expanded) {
          walk(childrenOf(node), depth + 1);
        }
      }
    }

    walk(fileTree, 0);
    return rows;
  }

  static String? extractWordAtCursor(String content, int line, int column) {
    final lines = content.split('\n');
    if (line < 1 || line > lines.length) return null;
    final row = lines[line - 1];
    if (column < 1 || column > row.length + 1) return null;
    final index = column - 1;
    final before = row.substring(0, index.clamp(0, row.length));
    final after = row.substring(index.clamp(0, row.length));
    final left = RegExp(r'[\w${}@&.]+$').firstMatch(before)?.group(0) ?? '';
    final right = RegExp(r'^[\w${}@&.]+').firstMatch(after)?.group(0) ?? '';
    final token = '$left$right'.trim();
    return token.isEmpty ? null : token;
  }

  /// Prefer Robot cell under the caret (multi-word keywords), else word token.
  static String? extractRobotTokenAt(String content, int line, int column) {
    final lines = content.split('\n');
    if (line < 1 || line > lines.length) return null;
    final row = lines[line - 1];
    if (row.startsWith(' ') || row.startsWith('\t')) {
      final cells = row
          .trim()
          .split(RegExp(r'[ \t]{2,}|\t+'))
          .where((cell) => cell.isNotEmpty)
          .toList();
      if (cells.isNotEmpty) {
        var keywordIndex = 0;
        if (RegExp(r'^[\$@&%]').hasMatch(cells.first) && cells.length > 1) {
          keywordIndex = 1;
        }
        // Locate cell by scanning separators from the left of the caret.
        final prefix = row.substring(0, (column - 1).clamp(0, row.length));
        final beforeCells = prefix
            .trim()
            .split(RegExp(r'[ \t]{2,}|\t+'))
            .where((cell) => cell.isNotEmpty)
            .toList();
        final cellIndex = beforeCells.isEmpty
            ? keywordIndex
            : (beforeCells.length - 1).clamp(0, cells.length - 1);
        final cell = cells[cellIndex];
        if (cell.isNotEmpty) return cell;
      }
    }
    return extractWordAtCursor(content, line, column);
  }

  static List<SignatureParameterInfo> parametersFromDetail(String detail) {
    if (detail.trim().isEmpty) return const [];
    return detail
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .map((part) {
          var label = part;
          var documentation = '';
          final eq = part.indexOf('=');
          if (eq > 0) {
            label = part.substring(0, eq).trim();
            documentation = 'default: ${part.substring(eq + 1).trim()}';
          }
          return SignatureParameterInfo(
            label: label,
            documentation: documentation,
          );
        })
        .toList();
  }
}
