import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robot_studio/core/gateway/models/git_info.dart';
import 'package:robot_studio/presentation/git/branch_selector.dart';
import 'package:robot_studio/presentation/git/commit_panel.dart';
import 'package:robot_studio/presentation/git/history_panel.dart';
import 'package:robot_studio/presentation/git/source_control_page.dart';
import 'package:robot_studio/presentation/widgets/skeleton_list.dart';

void main() {
  testWidgets('SourceControlPage shows empty repository state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 900,
            child: SourceControlPage(
            status: const GitStatusInfo(
              repository: GitRepositoryInfo(isRepository: false),
            ),
            branches: const [],
            history: const [],
            selectedCommit: null,
            commitDetail: null,
            diff: null,
            selectedFiles: const {},
            selectedDiffFile: null,
            commitController: TextEditingController(),
            isLoading: false,
            isBusy: false,
            isLoadingHistory: false,
            isLoadingDiff: false,
            onRefresh: () {},
            onInit: () {},
            onToggleFile: (_) {},
            onSelectDiffFile: (_) {},
            onCommitAll: () {},
            onCommitSelected: () {},
            onSelectCommit: (_) {},
            onRefreshHistory: () {},
            onFetch: () {},
            onPull: () {},
            onPush: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Not a Git repository'), findsWidgets);
    expect(find.text('Initialize Git Repository'), findsOneWidget);
  });

  testWidgets('SourceControlPage loading skeleton matches two-column layout', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 900,
            child: SourceControlPage(
              status: null,
              branches: const [],
              history: const [],
              selectedCommit: null,
              commitDetail: null,
              diff: null,
              selectedFiles: const {},
              selectedDiffFile: null,
              commitController: TextEditingController(),
              isLoading: true,
              isBusy: false,
              isLoadingHistory: false,
              isLoadingDiff: false,
              onRefresh: () {},
              onInit: () {},
              onToggleFile: (_) {},
              onSelectDiffFile: (_) {},
              onCommitAll: () {},
              onCommitSelected: () {},
              onSelectCommit: (_) {},
              onRefreshHistory: () {},
              onFetch: () {},
              onPull: () {},
              onPush: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Source Control'), findsOneWidget);
    expect(find.byType(VerticalDivider), findsOneWidget);
    // Left changes list + right history list.
    expect(find.byType(SkeletonList), findsNWidgets(2));
  });

  testWidgets('SourceControlPage refresh keeps content instead of skeleton', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 900,
            child: SourceControlPage(
              status: const GitStatusInfo(
                repository: GitRepositoryInfo(
                  isRepository: true,
                  branch: 'main',
                  clean: false,
                ),
                changes: [
                  GitFileChangeInfo(
                    path: 'a.robot',
                    status: GitFileStatus.modified,
                  ),
                ],
              ),
              branches: const [],
              history: const [],
              selectedCommit: null,
              commitDetail: null,
              diff: null,
              selectedFiles: const {},
              selectedDiffFile: null,
              commitController: TextEditingController(),
              isLoading: true,
              isBusy: false,
              isLoadingHistory: false,
              isLoadingDiff: false,
              onRefresh: () {},
              onInit: () {},
              onToggleFile: (_) {},
              onSelectDiffFile: (_) {},
              onCommitAll: () {},
              onCommitSelected: () {},
              onSelectCommit: (_) {},
              onRefreshHistory: () {},
              onFetch: () {},
              onPull: () {},
              onPush: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('a.robot'), findsOneWidget);
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('SourceControlPage shows grouped changes', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 900,
            child: SourceControlPage(
            status: const GitStatusInfo(
              repository: GitRepositoryInfo(
                isRepository: true,
                branch: 'main',
                head: 'abc1234567890',
                clean: false,
              ),
              changes: [
                GitFileChangeInfo(
                  path: 'tests.robot',
                  status: GitFileStatus.modified,
                ),
                GitFileChangeInfo(
                  path: 'README.md',
                  status: GitFileStatus.untracked,
                ),
              ],
            ),
            branches: const [GitBranchInfo(name: 'main', current: true)],
            history: const [],
            selectedCommit: null,
            commitDetail: null,
            diff: null,
            selectedFiles: const {},
            selectedDiffFile: null,
            commitController: TextEditingController(),
            isLoading: false,
            isBusy: false,
            isLoadingHistory: false,
            isLoadingDiff: false,
            onRefresh: () {},
            onInit: () {},
            onToggleFile: (_) {},
            onSelectDiffFile: (_) {},
            onCommitAll: () {},
            onCommitSelected: () {},
            onSelectCommit: (_) {},
            onRefreshHistory: () {},
            onFetch: () {},
            onPull: () {},
            onPush: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Modified'), findsOneWidget);
    expect(find.text('Untracked'), findsOneWidget);
    expect(find.text('tests.robot'), findsOneWidget);
  });

  testWidgets('CommitPanel requires message for commit actions', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommitPanel(
            controller: controller,
            enabled: true,
            isBusy: false,
            selectedCount: 1,
            totalCount: 1,
            onCommit: () {},
            onCommitSelected: () {},
          ),
        ),
      ),
    );

    expect(find.text('Commit All'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Fix login test');
    await tester.pump();
    expect(find.text('Commit Selected (1)'), findsOneWidget);
  });

  testWidgets('BranchSelector lists branches', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchSelector(
            branches: const [
              GitBranchInfo(name: 'main', current: true),
              GitBranchInfo(name: 'feature/login'),
            ],
            currentBranch: 'main',
            enabled: true,
            onCheckout: (_) {},
            onCreateBranch: (_) {},
            onDeleteBranch: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('main'), findsOneWidget);
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    expect(find.text('feature/login'), findsOneWidget);
  });

  testWidgets('HistoryPanel shows commits and details', (
    WidgetTester tester,
  ) async {
    final commit = GitCommitInfo(
      hash: 'abc1234567890',
      shortHash: 'abc1234',
      author: 'Dev',
      email: 'dev@example.com',
      date: DateTime.utc(2026, 1, 1),
      message: 'Initial commit',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryPanel(
            commits: [commit],
            selected: commit,
            detail: GitCommitDetailInfo(
              hash: 'abc1234567890',
              shortHash: 'abc1234',
              author: 'Dev',
              email: 'dev@example.com',
              date: DateTime.utc(2026, 1, 1),
              message: 'Initial commit',
              files: const [
                GitFileChangeInfo(
                  path: 'tests.robot',
                  status: GitFileStatus.added,
                ),
              ],
            ),
            isLoading: false,
            onSelect: (_) {},
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Initial commit'), findsWidgets);
    expect(find.text('Changed files'), findsOneWidget);
  });
}
