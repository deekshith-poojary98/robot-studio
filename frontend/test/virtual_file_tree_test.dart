import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/core/gateway/models/file_info.dart';
import 'package:robot_studio/presentation/widgets/virtual_file_tree.dart';
import 'package:robot_studio/presentation/workspace/explorer_file_actions.dart';

FlatFileTreeRow _file(String name, {int depth = 0}) {
  return FlatFileTreeRow(
    node: FileTreeNode(
      name: name,
      path: '/tmp/$name',
      relativePath: name,
      isDir: false,
      suffix: name.contains('.') ? '.${name.split('.').last}' : '',
      children: const [],
    ),
    depth: depth,
    expanded: false,
    loading: false,
  );
}

FlatFileTreeRow _dir(String name, {int depth = 0, bool expanded = false}) {
  return FlatFileTreeRow(
    node: FileTreeNode(
      name: name,
      path: '/tmp/$name',
      relativePath: name,
      isDir: true,
      hasChildren: true,
      children: const [],
    ),
    depth: depth,
    expanded: expanded,
    loading: false,
  );
}

void main() {
  test('ExplorerFileActions validates names', () {
    expect(ExplorerFileActions.validateName(''), isNotNull);
    expect(ExplorerFileActions.validateName('  x'), isNotNull);
    expect(ExplorerFileActions.validateName('a/b'), isNotNull);
    expect(ExplorerFileActions.validateName('CON'), isNotNull);
    expect(ExplorerFileActions.validateName('ok.robot'), isNull);
    expect(
      ExplorerFileActions.validateName(
        'Login.robot',
        existingNames: ['Login.robot'],
      ),
      isNotNull,
    );
  });

  test('ExplorerFileActions suggests .robot extension', () {
    expect(ExplorerFileActions.robotSuggestion('Login'), 'Login.robot');
    expect(ExplorerFileActions.robotSuggestion('Login.robot'), isNull);
    expect(ExplorerFileActions.robotSuggestion(''), isNull);
  });

  test('ExplorerFileActions seeds robot suite template', () {
    final content = ExplorerFileActions.initialContentFor('Login.robot');
    expect(content, contains('*** Settings ***'));
    expect(content, contains('*** Variables ***'));
    expect(content, contains('*** Test Cases ***'));
    expect(content, contains('*** Keywords ***'));
    expect(content, contains('Example Test'));
    expect(ExplorerFileActions.initialContentFor('notes.txt'), isEmpty);
    expect(ExplorerFileActions.initialContentFor('lib.resource'), isEmpty);
  });

  testWidgets('VirtualFileTree builds only visible rows', (tester) async {
    final rows = List.generate(
      200,
      (i) => _file('suite_$i.robot'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: VirtualFileTree(
              rows: rows,
              onOpenFile: (_) {},
              onToggleDirectory: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('virtual-file-tree')), findsOneWidget);
    expect(find.text('suite_0.robot'), findsOneWidget);
    expect(find.text('suite_199.robot'), findsNothing);
  });

  testWidgets('VirtualFileTree toggles directories', (tester) async {
    var toggled = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            rows: [_dir('tests')],
            onOpenFile: (_) {},
            onToggleDirectory: (path) => toggled = path,
          ),
        ),
      ),
    );

    await tester.tap(find.text('tests'));
    expect(toggled, '/tmp/tests');
  });

  testWidgets('context menu exposes file actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            rows: [_file('Login.robot')],
            rootPath: '/tmp',
            onOpenFile: (_) {},
            onToggleDirectory: (_) {},
            onDeleteEntry: (_) async {},
            onDuplicateEntry: (_) async {},
            onCopyRelativePath: (_) {},
            onCopyAbsolutePath: (_) {},
            onRevealInOs: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Login.robot'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Copy Relative Path'), findsOneWidget);
    expect(find.text('Copy Absolute Path'), findsOneWidget);
  });

  testWidgets('inline rename commits on Enter', (tester) async {
    String? renamedPath;
    String? renamedTo;
    final key = GlobalKey<VirtualFileTreeState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            key: key,
            rows: [_file('Login.robot')],
            rootPath: '/tmp',
            onOpenFile: (_) {},
            onToggleDirectory: (_) {},
            onRenameEntry: ({required path, required newName}) async {
              renamedPath = path;
              renamedTo = newName;
            },
          ),
        ),
      ),
    );

    key.currentState!.beginRename('/tmp/Login.robot');
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Logout.robot');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(renamedPath, '/tmp/Login.robot');
    expect(renamedTo, 'Logout.robot');
  });

  testWidgets('rename keeping the same name is a no-op', (tester) async {
    var renameCalls = 0;
    final key = GlobalKey<VirtualFileTreeState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            key: key,
            rows: [_dir('test')],
            rootPath: '/tmp',
            onOpenFile: (_) {},
            onToggleDirectory: (_) {},
            onRenameEntry: ({required path, required newName}) async {
              renameCalls++;
            },
          ),
        ),
      ),
    );

    key.currentState!.beginRename('/tmp/test');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(renameCalls, 0);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('already exists'), findsNothing);
  });

  testWidgets('rename folder does not show robot Create suggestion', (
    tester,
  ) async {
    final key = GlobalKey<VirtualFileTreeState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            key: key,
            rows: [_dir('tests')],
            rootPath: '/tmp',
            onOpenFile: (_) {},
            onToggleDirectory: (_) {},
            onRenameEntry: ({required path, required newName}) async {},
          ),
        ),
      ),
    );

    key.currentState!.beginRename('/tmp/tests');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test');
    await tester.pump();

    expect(find.textContaining('Create'), findsNothing);
    expect(find.textContaining('.robot'), findsNothing);
  });

  testWidgets('new file appends .robot on submit without suggestion chip', (
    tester,
  ) async {
    String? createdName;
    final key = GlobalKey<VirtualFileTreeState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            key: key,
            rows: [_file('a.robot')],
            rootPath: '/tmp',
            onOpenFile: (_) {},
            onToggleDirectory: (_) {},
            onCreateEntry: ({
              required parentPath,
              required name,
              required isDirectory,
            }) async {
              createdName = name;
            },
          ),
        ),
      ),
    );

    key.currentState!.beginNewFile('/tmp');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Login');
    await tester.pump();

    expect(find.textContaining('Create '), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(createdName, 'Login.robot');
  });

  testWidgets('F2 starts rename when tree has focus', (tester) async {
    final key = GlobalKey<VirtualFileTreeState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            key: key,
            rows: [_file('Login.robot')],
            rootPath: '/tmp',
            selectedPath: '/tmp/Login.robot',
            onOpenFile: (_) {},
            onToggleDirectory: (_) {},
            onRenameEntry: ({required path, required newName}) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Login.robot'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('delete confirmation is owned by host callback', (tester) async {
    var deleteCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualFileTree(
            rows: [_file('Login.robot')],
            rootPath: '/tmp',
            onOpenFile: (_) {},
            onToggleDirectory: (_) {},
            onDeleteEntry: (_) async {
              deleteCalled = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Login.robot'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleteCalled, isTrue);
  });
}
