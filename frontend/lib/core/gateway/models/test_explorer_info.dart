class TestNodeInfo {
  const TestNodeInfo({
    required this.id,
    required this.kind,
    required this.name,
    this.path,
    this.line,
    this.projectId,
    this.status = TestNodeStatus.notRun,
    this.tags = const [],
    this.detail = '',
    this.children = const [],
  });

  factory TestNodeInfo.fromJson(Map<String, dynamic> json) {
    final children = (json['children'] as List<dynamic>? ?? const [])
        .map((item) => TestNodeInfo.fromJson(item as Map<String, dynamic>))
        .toList();
    return TestNodeInfo(
      id: json['id'] as String,
      kind: json['kind'] as String,
      name: json['name'] as String,
      path: json['path'] as String?,
      line: (json['line'] as num?)?.toInt(),
      projectId: json['project_id'] as String?,
      status: TestNodeStatus.fromApi(json['status'] as String? ?? 'not_run'),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      detail: json['detail'] as String? ?? '',
      children: children,
    );
  }

  final String id;
  final String kind;
  final String name;
  final String? path;
  final int? line;
  final String? projectId;
  final TestNodeStatus status;
  final List<String> tags;
  final String detail;
  final List<TestNodeInfo> children;

  bool get isRunnable =>
      kind == 'test' ||
      kind == 'task' ||
      kind == 'suite' ||
      kind == 'project' ||
      kind == 'workspace';

  /// Lazy suite/project shell from the backend — expand loads real children.
  bool get needsLazyExpand =>
      children.isEmpty &&
      detail == 'expand' &&
      (kind == 'suite' || kind == 'project' || kind == 'directory');

  bool get canExpand => children.isNotEmpty || needsLazyExpand;

  TestNodeInfo copyWith({
    List<TestNodeInfo>? children,
    String? detail,
    TestNodeStatus? status,
  }) {
    return TestNodeInfo(
      id: id,
      kind: kind,
      name: name,
      path: path,
      line: line,
      projectId: projectId,
      status: status ?? this.status,
      tags: tags,
      detail: detail ?? this.detail,
      children: children ?? this.children,
    );
  }

  TestNodeInfo replaceChild(String childId, TestNodeInfo replacement) {
    if (id == childId) return replacement;
    if (children.isEmpty) return this;
    return copyWith(
      children: [
        for (final child in children) child.replaceChild(childId, replacement),
      ],
    );
  }

  /// After a lazy tree reload, keep previously expanded suite/dir children so
  /// the UI does not flash empty while those nodes stay visually expanded.
  ///
  /// Returns the merged tree plus suite/dir nodes that should be re-fetched
  /// (e.g. to pick up post-run status).
  static ({TestNodeInfo tree, List<TestNodeInfo> refresh})
  retainHydratedChildren(TestNodeInfo previous, TestNodeInfo next) {
    final prevById = <String, TestNodeInfo>{};
    void index(TestNodeInfo node) {
      prevById[node.id] = node;
      for (final child in node.children) {
        index(child);
      }
    }

    index(previous);
    final refresh = <TestNodeInfo>[];

    TestNodeInfo merge(TestNodeInfo node) {
      final mergedKids = [for (final child in node.children) merge(child)];
      var result = node.copyWith(children: mergedKids);
      if (result.needsLazyExpand) {
        final prev = prevById[result.id];
        if (prev != null && prev.children.isNotEmpty && !prev.needsLazyExpand) {
          result = result.copyWith(children: prev.children, detail: '');
          final path = result.path;
          if (path != null && path.isNotEmpty) {
            refresh.add(result);
          }
        }
      }
      return result;
    }

    return (tree: merge(next), refresh: refresh);
  }
}

enum TestNodeStatus {
  pass,
  fail,
  skip,
  notRun,
  running;

  static TestNodeStatus fromApi(String value) {
    return switch (value) {
      'pass' => TestNodeStatus.pass,
      'fail' => TestNodeStatus.fail,
      'skip' => TestNodeStatus.skip,
      'running' => TestNodeStatus.running,
      _ => TestNodeStatus.notRun,
    };
  }

  String get label => switch (this) {
    TestNodeStatus.pass => 'PASS',
    TestNodeStatus.fail => 'FAIL',
    TestNodeStatus.skip => 'SKIP',
    TestNodeStatus.notRun => 'NOT RUN',
    TestNodeStatus.running => 'RUNNING',
  };
}
