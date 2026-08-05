import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/content_search_info.dart';
import 'package:robot_studio/presentation/search/find_in_files_panel.dart';

void main() {
  testWidgets('Find in Files auto-expands single-file results', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FindInFilesPanel(
            hasProject: true,
            onSearch: (query) async {
              return ContentSearchResultInfo(
                query: query,
                truncated: false,
                filesScanned: 1,
                files: [
                  ContentFileHitsInfo(
                    path: '/proj/tests/login.robot',
                    matchCount: 1,
                    matches: [
                      ContentMatchInfo(
                        line: 8,
                        column: 5,
                        text: '    Log    $query',
                        enclosing: const EnclosingSymbolInfo(
                          kind: 'test_case',
                          name: 'Valid Login',
                          line: 5,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
            onOpenMatch: (_, _, _) {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 matches in 1 files'), findsOneWidget);
    expect(find.textContaining('login.robot'), findsOneWidget);
    expect(find.textContaining('Valid Login'), findsOneWidget);
    expect(find.textContaining('Log    hello'), findsOneWidget);
  });

  testWidgets('Find in Files remembers expansion across searches', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var call = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FindInFilesPanel(
            hasProject: true,
            onSearch: (query) async {
              call++;
              return ContentSearchResultInfo(
                query: query,
                truncated: false,
                filesScanned: 2,
                files: [
                  ContentFileHitsInfo(
                    path: '/proj/a.robot',
                    matchCount: 1,
                    matches: [
                      ContentMatchInfo(line: 1, column: 1, text: 'A $query'),
                    ],
                  ),
                  ContentFileHitsInfo(
                    path: '/proj/b.robot',
                    matchCount: 1,
                    matches: [
                      ContentMatchInfo(line: 1, column: 1, text: 'B $query'),
                    ],
                  ),
                ],
              );
            },
            onOpenMatch: (_, _, _) {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'one');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // Multi-file: collapsed by default — match lines hidden.
    expect(find.textContaining('A one'), findsNothing);

    await tester.tap(find.textContaining('a.robot'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A one'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'two');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(call, greaterThanOrEqualTo(2));
    // Expansion remembered for a.robot.
    expect(find.textContaining('A two'), findsOneWidget);
  });
}
