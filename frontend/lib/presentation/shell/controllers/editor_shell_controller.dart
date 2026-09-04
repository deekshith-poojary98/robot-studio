import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/gateway/transport_gateway.dart';
import '../../../core/logging/app_logger.dart';
import '../../editor/editor_syntax.dart' as syntax;
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
  DocumentAnalysisInfo? documentAnalysis;
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
  DocumentSymbolNode? activeDocumentSymbol;
  List<CompletionItemInfo> completionItems = [];
  List<DiagnosticInfo> diagnostics = [];
  List<DiagnosticInfo> workspaceProblems = [];
  SignatureHelpInfo? hoverTooltip;

  /// True when [hoverTooltip] came from pointer hover, not caret refresh.
  /// Python only shows the card on hover; caret refresh must not wipe it.
  bool _hoverFromPointer = false;
  IndexedSymbolInfo? peekDefinition;
  bool loadingLanguageFeatures = false;
  bool loadingFileTree = false;

  Timer? languageDebounce;
  Timer? hoverDebounce;
  Timer? cursorUiDebounce;
  Timer? statusTimer;
  int _hoverRequestId = 0;
  int _languageRequestId = 0;

  static bool isPythonPath(String path) => syntax.isPythonPath(path);

  static bool isRobotPath(String path) => syntax.isRobotPath(path);

  static bool isSourcePath(String path) => syntax.isSourcePath(path);

  static const _cursorUiDebounce = Duration(milliseconds: 80);

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
    cursorUiDebounce?.cancel();
    statusTimer?.cancel();
  }

  void reset() {
    clearActiveDocument();
    tabs = [];
    workspaceProblems = [];
    statusTimer?.cancel();
    statusTimer = null;
    statusMessage = null;
    fileTree = [];
    expandedDirs.clear();
    childrenByPath.clear();
    loadingDirs.clear();
    loadingFileTree = false;
    recentFiles = [];
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
    // re_editor notifies on mount (delegate=) with unchanged text — skip so we
    // do not setState while the editor is still building.
    if (tabs[tabIndex].content == content) return;
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
    syncActiveSymbol(line);
    scheduleLanguageRefresh();
    _scheduleCursorUiNotify();
  }

  /// Status bar / outline chrome — debounced so fast typing does not rebuild
  /// the whole shell (and re-enter parent→controller content sync) per key.
  void _scheduleCursorUiNotify() {
    cursorUiDebounce?.cancel();
    cursorUiDebounce = Timer(_cursorUiDebounce, () {
      cursorUiDebounce = null;
      if (isMounted()) notify();
    });
  }

  /// Python resolves in-process in ~20ms, so it can afford a short debounce.
  /// Robot still spawns a parser per request and needs the longer one.
  static const _pythonDebounce = Duration(milliseconds: 120);
  static const _robotDebounce = Duration(milliseconds: 350);

  void scheduleLanguageRefresh() {
    final path = activePath;
    final delay = path != null && isPythonPath(path)
        ? _pythonDebounce
        : _robotDebounce;
    languageDebounce?.cancel();
    languageDebounce = Timer(delay, () {
      unawaited(refreshLanguageFeatures());
    });
  }

  /// Drop stale Robot completions / signature when switching editor tabs.
  void onActiveTabChanged() {
    completionItems = [];
    hoverTooltip = null;
    _hoverFromPointer = false;
    languageDebounce?.cancel();
    scheduleLanguageRefresh();
    notify();
  }

  Future<void> refreshLanguageFeatures() async {
    final tab = activeTab;
    if (tab == null || workspace() == null) return;
    final isRobot = isRobotPath(tab.path);
    final isPython = isPythonPath(tab.path);
    if (!isRobot && !isPython) {
      if (!isMounted()) return;
      completionItems = [];
      diagnostics = [];
      hoverTooltip = null;
      _hoverFromPointer = false;
      notify();
      return;
    }

    // Requests are debounced, not serialized: a slow reply must never overwrite
    // results computed for a later caret position.
    final requestId = ++_languageRequestId;
    final requestPath = tab.path;

    // Keep showing the current Problems list while refresh runs — never flash
    // a skeleton on every keystroke.
    try {
      final token =
          extractWordAtCursor(tab.content, cursorLine, cursorColumn) ?? '';
      // Python signature / docs are mouse-hover only (requestHoverTooltip).
      // Caret-driven signature help is Robot-only — otherwise just parking the
      // caret on a line pops the info card.
      final futures = <Future<Object?>>[
        gateway.languageCompletion(
          filePath: tab.path,
          line: cursorLine,
          column: cursorColumn,
          content: tab.content,
          query: token,
        ),
        gateway.languageDiagnostics(filePath: tab.path, content: tab.content),
        if (isRobot)
          gateway.languageSignatureHelp(
            filePath: tab.path,
            line: cursorLine,
            column: cursorColumn,
            content: tab.content,
          ),
      ];
      final results = await Future.wait(futures);
      if (!isMounted() || !_isCurrentLanguageRequest(requestId, requestPath)) {
        return;
      }
      completionItems = results[0]! as List<CompletionItemInfo>;
      diagnostics = results[1]! as List<DiagnosticInfo>;
      if (isRobot) {
        // Caret-driven signature: update when resolved; clear when leaving a call.
        hoverTooltip = results[2] as SignatureHelpInfo?;
        _hoverFromPointer = false;
      } else if (!_hoverFromPointer) {
        // Drop any leftover caret card when navigating Python files.
        hoverTooltip = null;
      }
      // Update Problems for the active file in place (no full-workspace rescan).
      workspaceProblems = [
        ...workspaceProblems.where((item) => item.filePath != requestPath),
        ...diagnostics,
      ];
      // Keep outline / folding in sync with the live buffer.
      try {
        final analysis = await gateway.analyzeDocument(
          filePath: tab.path,
          content: tab.content,
        );
        if (!isMounted() ||
            !_isCurrentLanguageRequest(requestId, requestPath)) {
          return;
        }
        documentAnalysis = analysis;
        documentOutline = analysis.flattenIndexed();
        syncActiveSymbol(cursorLine);
      } catch (_) {
        // Outline refresh is best-effort alongside completion/diagnostics.
      }
      loadingLanguageFeatures = false;
      notify();
    } catch (error) {
      if (!isMounted() || !_isCurrentLanguageRequest(requestId, requestPath)) {
        return;
      }
      loadingLanguageFeatures = false;
      notify();
      AppLogger.debug('Language refresh failed', tag: 'Shell', data: '$error');
    }
  }

  bool _isCurrentLanguageRequest(int requestId, String path) =>
      requestId == _languageRequestId && activeTab?.path == path;

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
    _hoverFromPointer = false;
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
    final isPython = isPythonPath(tab.path);
    if (!isSourcePath(tab.path)) {
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
        hover: true,
      );
      if (!isMounted() || requestId != _hoverRequestId) return;
      if (signature != null) {
        hoverTooltip = signature;
        _hoverFromPointer = true;
        notify();
        return;
      }

      if (isPython) {
        final hover = await gateway.languageHover(
          filePath: tab.path,
          line: line,
          column: column,
          content: tab.content,
        );
        if (!isMounted() || requestId != _hoverRequestId) return;
        if (hover == null) {
          hoverTooltip = null;
          _hoverFromPointer = false;
          notify();
          return;
        }
        hoverTooltip = SignatureHelpInfo(
          keyword: hover.name,
          documentation: hover.documentation,
          detail: hover.detail.isNotEmpty ? hover.detail : hover.kind.label,
          parameters: [SignatureParameterInfo(label: hover.kind.label)],
        );
        _hoverFromPointer = true;
        notify();
        return;
      }

      final token = extractRobotTokenAt(tab.content, line, column);
      if (token == null || token.isEmpty) {
        hoverTooltip = null;
        _hoverFromPointer = false;
        notify();
        return;
      }

      final hover = await gateway.languageHover(
        filePath: tab.path,
        line: line,
        column: column,
        content: tab.content,
        name: token,
      );
      if (!isMounted() || requestId != _hoverRequestId) return;
      if (hover == null) {
        hoverTooltip = null;
        _hoverFromPointer = false;
        notify();
        return;
      }
      final argChips = _argumentChipsFromHoverDetail(hover.detail);
      if (argChips.isNotEmpty) {
        hoverTooltip = SignatureHelpInfo(
          keyword: hover.name,
          documentation: hover.documentation,
          detail: hover.detail,
          libraryName: hover.kind.label,
          parameters: argChips,
        );
      } else {
        // Symbol hover (test case, keyword definition, …): singular kind badge.
        hoverTooltip = SignatureHelpInfo(
          keyword: hover.name,
          documentation: hover.documentation,
          detail: hover.kind.label,
          parameters: [SignatureParameterInfo(label: hover.kind.label)],
        );
      }
      _hoverFromPointer = true;
      notify();
    } catch (error) {
      if (!isMounted() || requestId != _hoverRequestId) return;
      AppLogger.debug('Hover tooltip failed', tag: 'Shell', data: '$error');
      hoverTooltip = null;
      _hoverFromPointer = false;
      notify();
    }
  }

  Future<void> refreshWorkspaceProblems() async {
    final problems = <DiagnosticInfo>[];
    for (final tab in tabs) {
      if (!isSourcePath(tab.path)) continue;
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

  Future<void> loadOutline(String path, {String? content}) async {
    loadingOutline = true;
    selectedOutlineSymbol = null;
    activeDocumentSymbol = null;
    notify();
    try {
      var buffer = content;
      if (buffer == null) {
        for (final tab in tabs) {
          if (tab.path == path) {
            buffer = tab.content;
            break;
          }
        }
      }
      if (buffer != null) {
        documentAnalysis = await gateway.analyzeDocument(
          filePath: path,
          content: buffer,
        );
        documentOutline = documentAnalysis!.flattenIndexed();
      } else {
        documentOutline = await gateway.documentSymbols(path);
        documentAnalysis = null;
      }
      if (!isMounted()) return;
      syncActiveSymbol(cursorLine);
      loadingOutline = false;
      notify();
    } catch (_) {
      if (!isMounted()) return;
      documentOutline = [];
      documentAnalysis = null;
      loadingOutline = false;
      notify();
    }
  }

  /// Drops every per-document artifact after the last tab closes.
  ///
  /// Outline renders from [documentAnalysis], not [documentOutline], so
  /// clearing only the flat list left the previous file's tree on screen with
  /// no editor open.
  void clearActiveDocument() {
    activePath = null;
    documentOutline = [];
    documentAnalysis = null;
    selectedOutlineSymbol = null;
    activeDocumentSymbol = null;
    completionItems = [];
    diagnostics = [];
    hoverTooltip = null;
    _hoverFromPointer = false;
    peekDefinition = null;
    loadingOutline = false;
    jumpToLine = null;
    jumpToColumn = null;
    cursorLine = 1;
    cursorColumn = 1;
    languageDebounce?.cancel();
    hoverDebounce?.cancel();
  }

  void syncActiveSymbol(int line) {
    cursorLine = line;
    final root = documentAnalysis?.root;
    if (root == null) {
      activeDocumentSymbol = null;
      return;
    }
    final hit = root.findAtLine(line);
    activeDocumentSymbol = hit;
    if (hit != null && _trackableOutlineKinds.contains(hit.kind)) {
      selectedOutlineSymbol = hit.toIndexed(documentAnalysis!.filePath);
    }
  }

  /// Kinds the outline follows the caret into. Python classes/functions/methods
  /// belong here too, or the Outline pane never tracks a `.py` buffer.
  static const _trackableOutlineKinds = {
    SymbolKind.keyword,
    SymbolKind.testCase,
    SymbolKind.section,
    SymbolKind.keywordCall,
    SymbolKind.control,
    SymbolKind.variable,
    SymbolKind.classKind,
    SymbolKind.function,
    SymbolKind.method,
  };

  /// Explorer tree keys must be slash-stable: Windows backends return `\`,
  /// while create/refresh paths often use `/`. Mixing them left expanded
  /// folders stuck on an empty cache after new files were created.
  static String normalizeTreePath(String path) => path.replaceAll('\\', '/');

  String _treeKey(String path) => normalizeTreePath(path);

  /// Resolve a possibly-relative directory to an absolute tree key.
  String _absoluteTreeKey(String path, String workspaceRoot) {
    final normalized = _treeKey(path);
    final root = _treeKey(workspaceRoot).replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return root;
    final isAbsolute =
        normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:/').hasMatch(normalized);
    if (isAbsolute) return normalized;
    return '$root/$normalized';
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
    final normalized = _treeKey(path);
    final wsPath = _treeKey(ws.path);
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
    final root = _treeKey(workspaceRoot);
    final normalizedDir = directoryPath == null || directoryPath.isEmpty
        ? null
        : _treeKey(directoryPath);
    final isRoot = normalizedDir == null || normalizedDir == root;

    try {
      if (isRoot) {
        final fresh = await gateway.listFileTree(depth: 0);
        if (!isMounted()) return;
        fileTree = fresh;
        _pruneMissingTreeState(fresh);
        notify();
        return;
      }

      final parent = _absoluteTreeKey(normalizedDir, root);
      // Only hit the API when the parent is visible (expanded or cached).
      if (!expandedDirs.contains(parent) &&
          !childrenByPath.containsKey(parent)) {
        // Parent collapsed — still flip hasChildren so the chevron appears.
        _markDirHasChildren(parent, true);
        notify();
        return;
      }
      final kids = await gateway.listFileTree(path: parent, depth: 0);
      if (!isMounted()) return;
      childrenByPath[parent] = kids;
      _markDirHasChildren(parent, kids.isNotEmpty);
      _pruneMissingTreeState(fileTree);
      notify();
    } catch (_) {
      // Ignore transient FS races during delete/rename storms.
    }
  }

  void _markDirHasChildren(String directoryPath, bool hasChildren) {
    final target = _treeKey(directoryPath);
    bool walk(List<FileTreeNode> nodes) {
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        if (_treeKey(node.path) == target) {
          if (node.hasChildren != hasChildren) {
            nodes[i] = node.copyWith(hasChildren: hasChildren);
          }
          return true;
        }
        final cached = childrenByPath[_treeKey(node.path)];
        if (cached != null && walk(cached)) return true;
      }
      return false;
    }

    walk(fileTree);
  }

  void removePathFromTree(String path) {
    final normalized = _treeKey(path);
    fileTree = _filterNodes(fileTree, normalized);
    final updated = <String, List<FileTreeNode>>{};
    for (final entry in childrenByPath.entries) {
      final key = _treeKey(entry.key);
      if (key == normalized || key.startsWith('$normalized/')) {
        continue;
      }
      updated[key] = _filterNodes(entry.value, normalized);
    }
    childrenByPath
      ..clear()
      ..addAll(updated);
    expandedDirs.removeWhere((item) {
      final key = _treeKey(item);
      return key == normalized || key.startsWith('$normalized/');
    });
    loadingDirs.removeWhere((item) {
      final key = _treeKey(item);
      return key == normalized || key.startsWith('$normalized/');
    });
    notify();
  }

  List<FileTreeNode> _filterNodes(List<FileTreeNode> nodes, String removed) {
    return nodes.where((node) {
      final p = _treeKey(node.path);
      return p != removed && !p.startsWith('$removed/');
    }).toList();
  }

  void _pruneMissingTreeState(List<FileTreeNode> roots) {
    final alive = <String>{};
    void walk(List<FileTreeNode> nodes) {
      for (final node in nodes) {
        alive.add(_treeKey(node.path));
        final cached = childrenByPath[_treeKey(node.path)];
        if (cached != null) walk(cached);
      }
    }

    walk(roots);
    for (final entry in childrenByPath.entries) {
      walk(entry.value);
    }
    expandedDirs.removeWhere((path) => !alive.contains(_treeKey(path)));
    childrenByPath.removeWhere((key, _) => !alive.contains(_treeKey(key)));
    loadingDirs.removeWhere((path) => !alive.contains(_treeKey(path)));
  }

  Future<void> toggleDirectory(String path) async {
    final key = _treeKey(path);
    if (expandedDirs.contains(key)) {
      expandedDirs.remove(key);
      notify();
      return;
    }
    await ensureExpanded(path);
  }

  /// Expand [path] if collapsed, loading children when needed.
  Future<void> ensureExpanded(String path) async {
    final key = _treeKey(path);
    if (expandedDirs.contains(key) && childrenByPath.containsKey(key)) {
      return;
    }
    expandedDirs.add(key);
    if (!childrenByPath.containsKey(key)) {
      loadingDirs.add(key);
      notify();
      try {
        final kids = await gateway.listFileTree(path: path, depth: 0);
        childrenByPath[key] = kids;
      } catch (_) {
        childrenByPath[key] = const [];
      } finally {
        loadingDirs.remove(key);
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
    final key = _treeKey(node.path);
    if (childrenByPath.containsKey(key)) {
      return childrenByPath[key]!;
    }
    if (node.children.isNotEmpty) return node.children;
    return const [];
  }

  List<FlatFileTreeRow> visibleFileRows() {
    final rows = <FlatFileTreeRow>[];

    void walk(List<FileTreeNode> nodes, int depth) {
      for (final node in nodes) {
        final key = _treeKey(node.path);
        final expanded = expandedDirs.contains(key);
        final loading = loadingDirs.contains(key);
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

  /// Inclusive 1-based column spans for Robot cells (2+ spaces or tabs).
  static List<({String text, int start, int end})> robotCellSpans(String row) {
    final spans = <({String text, int start, int end})>[];
    var i = 0;
    final n = row.length;
    while (i < n && (row[i] == ' ' || row[i] == '\t')) {
      i += 1;
    }
    while (i < n) {
      final start = i;
      while (i < n) {
        if (row[i] == '\t') break;
        if (row[i] == ' ' &&
            i + 1 < n &&
            (row[i + 1] == ' ' || row[i + 1] == '\t')) {
          break;
        }
        i += 1;
      }
      final cell = row.substring(start, i);
      if (cell.isNotEmpty) {
        spans.add((text: cell, start: start + 1, end: i));
      }
      final rest = row.substring(i);
      final sep = RegExp(r'[ \t]{2,}|\t+').matchAsPrefix(rest);
      if (sep == null) break;
      i += sep.end;
    }
    return spans;
  }

  /// `${x}` from `${x}=` / `${x}[id]` / `${x.json()}`.
  static String? variableTokenFromCell(String cell) {
    var text = cell.trim();
    if (text.endsWith('=')) {
      text = text.substring(0, text.length - 1).trimRight();
    }
    return RegExp(r'^[\$@&%]\{[^}]+\}').firstMatch(text)?.group(0);
  }

  /// Prefer Robot cell under the caret (multi-word keywords), else word token.
  static String? extractRobotTokenAt(String content, int line, int column) {
    final lines = content.split('\n');
    if (line < 1 || line > lines.length) return null;
    final row = lines[line - 1];
    if (row.startsWith(' ') || row.startsWith('\t')) {
      for (final span in robotCellSpans(row)) {
        if (column >= span.start && column <= span.end) {
          return variableTokenFromCell(span.text) ?? span.text;
        }
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

  /// True when [detail] looks like keyword args (`a, b=1`), not a section label.
  @visibleForTesting
  static List<SignatureParameterInfo> argumentChipsFromHoverDetail(
    String detail,
  ) => _argumentChipsFromHoverDetail(detail);

  static List<SignatureParameterInfo> _argumentChipsFromHoverDetail(
    String detail,
  ) {
    final trimmed = detail.trim();
    if (trimmed.isEmpty) return const [];
    // Section / kind labels from the parser (and tag annotations).
    final lower = trimmed.toLowerCase();
    if (lower == 'test case' ||
        lower == 'test cases' ||
        lower == 'task' ||
        lower == 'tasks' ||
        lower == 'keyword' ||
        lower == 'keywords' ||
        lower.startsWith('test case|') ||
        lower.startsWith('test cases|') ||
        lower.startsWith('task|') ||
        lower.startsWith('tasks|')) {
      return const [];
    }
    // Custom keyword [Arguments] often look like `${a}, ${b}=2` (or a single
    // `${name}` with no comma) — treat RF variables as signature detail.
    final looksLikeArgs =
        trimmed.contains(',') ||
        trimmed.contains('=') ||
        trimmed.contains(':') ||
        RegExp(r'[\$@&%]\{').hasMatch(trimmed);
    if (!looksLikeArgs) return const [];
    return parametersFromDetail(trimmed);
  }
}
