import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/index_info.dart';
import 'package:robot_studio/core/gateway/models/language_info.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/editor/document_outline.dart';

void main() {
  DocumentSymbolNode sampleTree() {
    return const DocumentSymbolNode(
      id: 'suite:login.robot',
      name: 'login.robot',
      kind: SymbolKind.testSuite,
      line: 1,
      children: [
        DocumentSymbolNode(
          id: 'section:keywords',
          name: '*** Keywords ***',
          kind: SymbolKind.section,
          line: 10,
          children: [
            DocumentSymbolNode(
              id: 'keyword:Open Browser',
              name: 'Open Browser To Login Page',
              kind: SymbolKind.keyword,
              line: 12,
              children: [
                DocumentSymbolNode(
                  id: 'call:Open Browser',
                  name: 'Open Browser',
                  kind: SymbolKind.keywordCall,
                  line: 13,
                ),
              ],
            ),
          ],
        ),
        DocumentSymbolNode(
          id: 'section:tests',
          name: '*** Test Cases ***',
          kind: SymbolKind.section,
          line: 20,
          children: [
            DocumentSymbolNode(
              id: 'test:Valid Login',
              name: 'Valid Login',
              kind: SymbolKind.testCase,
              line: 22,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> pumpOutline(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DocumentOutlinePanel(
            isLoading: false,
            root: sampleTree(),
            filePath: '/ws/login.robot',
            initiallyExpanded: true,
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('outline seeds sections open and Collapse All hides children', (
    tester,
  ) async {
    await pumpOutline(tester);

    // Sections start expanded, so keyword / test names are visible.
    expect(find.text('*** Keywords ***'), findsOneWidget);
    expect(find.text('Open Browser To Login Page'), findsOneWidget);
    expect(find.text('Valid Login'), findsOneWidget);

    await tester.tap(find.byKey(const Key('outline-collapse-all')));
    await tester.pumpAndSettle();

    // Sections remain listed; everything nested under them is gone.
    expect(find.text('*** Keywords ***'), findsOneWidget);
    expect(find.text('*** Test Cases ***'), findsOneWidget);
    expect(find.text('Open Browser To Login Page'), findsNothing);
    expect(find.text('Valid Login'), findsNothing);
    expect(find.text('Open Browser'), findsNothing);
  });

  testWidgets('outline empties when the last editor closes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpWith(DocumentSymbolNode? root, String filePath) {
      return tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: DocumentOutlinePanel(
              isLoading: false,
              root: root,
              filePath: filePath,
              initiallyExpanded: true,
              embedded: true,
            ),
          ),
        ),
      );
    }

    await pumpWith(sampleTree(), '/ws/login.robot');
    await tester.pumpAndSettle();
    expect(find.text('Valid Login'), findsOneWidget);

    // Closing the last tab clears the analysis root.
    await pumpWith(null, '');
    await tester.pumpAndSettle();

    expect(find.text('Valid Login'), findsNothing);
    expect(find.text('*** Keywords ***'), findsNothing);
    expect(find.text('No symbols'), findsOneWidget);
  });

  testWidgets('outline filter does not carry over to the next file', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpWith(String filePath) {
      return tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: DocumentOutlinePanel(
              isLoading: false,
              root: sampleTree(),
              filePath: filePath,
              initiallyExpanded: true,
              embedded: true,
            ),
          ),
        ),
      );
    }

    await pumpWith('/ws/login.robot');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Valid');
    await tester.pumpAndSettle();
    expect(find.text('Open Browser To Login Page'), findsNothing);

    await pumpWith('/ws/other.robot');
    await tester.pumpAndSettle();

    expect(find.text('Open Browser To Login Page'), findsOneWidget);
    expect(find.text('Valid Login'), findsOneWidget);
  });

  testWidgets('outline pane can be dragged taller and reset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              DocumentOutlinePanel(
                isLoading: false,
                root: sampleTree(),
                filePath: '/ws/login.robot',
                initiallyExpanded: true,
                embedded: true,
                maxHeight: 600,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double paneHeight() {
      final body = find.byType(DocumentOutlinePanel);
      final outline = find.descendant(
        of: body,
        matching: find.byType(TextField),
      );
      // The sized pane is the SizedBox wrapping the outline body.
      return tester
          .getSize(
            find.ancestor(of: outline, matching: find.byType(SizedBox)).last,
          )
          .height;
    }

    final initial = paneHeight();
    expect(initial, closeTo(220, 1));

    // Drag the sash upward — the outline grows. The recognizer eats touch slop
    // before the first update, so assert the growth, not an exact pixel count.
    final handle = find.byKey(const Key('outline-resize-handle'));
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(0, -120));
    await tester.pumpAndSettle();
    final grown = paneHeight();
    expect(grown, greaterThan(initial + 80));
    expect(grown, lessThanOrEqualTo(initial + 120));

    // Beyond the cap it stops growing rather than starving the tree.
    await tester.drag(handle, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(paneHeight(), closeTo(600, 1));

    // Double-tap restores the default.
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(paneHeight(), closeTo(220, 1));
  });

  testWidgets('collapse-all stays hidden for a flat symbol list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DocumentOutlinePanel(
            isLoading: false,
            symbols: const [
              IndexedSymbolInfo(
                id: '1',
                name: 'Alone',
                kind: SymbolKind.keyword,
                filePath: '/ws/a.robot',
                line: 1,
              ),
            ],
            filePath: '/ws/a.robot',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('outline-collapse-all')), findsNothing);
    expect(find.text('Alone'), findsOneWidget);
  });
}
