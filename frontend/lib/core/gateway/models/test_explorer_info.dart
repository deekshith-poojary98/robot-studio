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
