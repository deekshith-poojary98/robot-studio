import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/presentation/shell/controllers/editor_shell_controller.dart';

class _TreeGateway implements TransportGateway {
  List<FileTreeNode> children = const [];

  @override
  Future<List<FileTreeNode>> listFileTree({String? path, int depth = 0}) async {
    return List<FileTreeNode>.from(children);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('normalizeTreePath unifies Windows separators', () {
    expect(
      EditorShellController.normalizeTreePath(
        r'C:\Users\deeks\Documents\proj\tests',
      ),
      'C:/Users/deeks/Documents/proj/tests',
    );
  });

  test('refreshParentOf updates children when expand used backslashes', () async {
    // Reproduce the Windows bug: expand keys with `\`, create/refresh uses `/`.
    const winTests = r'C:\Users\deeks\Documents\proj\tests';
    const winFile = r'C:\Users\deeks\Documents\proj\tests\test.robot';
    const posixTests = 'C:/Users/deeks/Documents/proj/tests';

    final gateway = _TreeGateway();
    final controller = EditorShellController(
      gateway: gateway,
      notify: () {},
      isMounted: () => true,
      workspace: () => WorkspaceInfo(
        id: 'ws',
        name: 'proj',
        path: r'C:\Users\deeks\Documents\proj',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );

    controller.fileTree = [
      const FileTreeNode(
        name: 'tests',
        path: winTests,
        relativePath: 'tests',
        isDir: true,
        hasChildren: false,
      ),
    ];

    // User expands the empty folder (backend path uses backslashes).
    await controller.ensureExpanded(winTests);
    expect(controller.childrenOf(controller.fileTree.first), isEmpty);

    // File appears on disk; create/refresh uses forward-slash absolute path.
    gateway.children = [
      const FileTreeNode(
        name: 'test.robot',
        path: winFile,
        relativePath: 'tests/test.robot',
        isDir: false,
        suffix: '.robot',
      ),
    ];
    await controller.refreshParentOf(winFile);

    final kids = controller.childrenOf(controller.fileTree.first);
    expect(kids, hasLength(1));
    expect(kids.first.name, 'test.robot');
    expect(
      controller.expandedDirs,
      contains(posixTests),
      reason: 'tree keys must stay slash-normalized',
    );

    controller.dispose();
  });
}
