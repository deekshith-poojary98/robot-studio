import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/core/gateway/models/file_info.dart';
import 'package:robot_studio/presentation/editor/editor_tabs_bar.dart';

void main() {
  testWidgets('EditorTabsBar context menu exposes close and path actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final actions = <EditorTabContextAction>[];
    final tabs = [
      EditorTabInfo(
        path: '/tmp/a.robot',
        content: 'a',
        savedContent: 'a',
        mtime: 1,
      ),
      EditorTabInfo(
        path: '/tmp/b.robot',
        content: 'b',
        savedContent: 'b',
        mtime: 1,
      ),
      EditorTabInfo(
        path: '/tmp/c.robot',
        content: 'c',
        savedContent: 'c',
        mtime: 1,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorTabsBar(
            tabs: tabs,
            activePath: tabs[1].path,
            onSelect: (_) {},
            onClose: (_) {},
            onContextAction: (_, action) => actions.add(action),
          ),
        ),
      ),
    );

    await tester.tap(find.text('b.robot'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Close Others'), findsOneWidget);
    expect(find.text('Close All'), findsOneWidget);
    expect(find.text('Close Saved'), findsOneWidget);
    expect(find.text('Close to the Right'), findsOneWidget);
    expect(find.text('Copy Relative Path'), findsOneWidget);
    expect(find.text('Copy Absolute Path'), findsOneWidget);
    expect(find.textContaining('Reveal in'), findsOneWidget);

    await tester.tap(find.text('Close Others'));
    await tester.pumpAndSettle();
    expect(actions, [EditorTabContextAction.closeOthers]);
  });

  testWidgets('Close to the Right disabled on last tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final actions = <EditorTabContextAction>[];
    final tabs = [
      EditorTabInfo(
        path: '/tmp/a.robot',
        content: 'a',
        savedContent: 'a',
        mtime: 1,
      ),
      EditorTabInfo(
        path: '/tmp/b.robot',
        content: 'b',
        savedContent: 'b',
        mtime: 1,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorTabsBar(
            tabs: tabs,
            activePath: tabs[1].path,
            onSelect: (_) {},
            onClose: (_) {},
            onContextAction: (_, action) => actions.add(action),
          ),
        ),
      ),
    );

    await tester.tap(find.text('b.robot'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close to the Right'));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
  });
}
