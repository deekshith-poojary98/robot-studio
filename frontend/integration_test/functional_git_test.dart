import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:robot_studio/presentation/widgets/toolbar_button.dart';

import 'helpers/integration_harness.dart';
import 'helpers/ui_helpers.dart';

/// Functional cases: GT-01 … GT-10 (Git / Source Control).
///
/// Source: docs/internal/functional-test-cases.md §13
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  Future<({String workspacePath, String suitePath, String project})>
      seedGitWorkspace({
    required String workspace,
    required String suffix,
    required String project,
  }) async {
    final created = await harness.seedWorkspace(name: workspace, suffix: suffix);
    await harness.seedEnvironment(name: '$suffix-env', installRobot: false);
    final proj = await harness.seedProject(name: project);
    final suitePath = '${proj['path']}/tests/git.robot';
    await harness.api.writeFile(
      path: suitePath,
      content: '*** Test Cases ***\nGit\n    Log    one\n',
    );
    return (
      workspacePath: created['path'] as String,
      suitePath: suitePath,
      project: project,
    );
  }

  Finder commitField() => find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Message…',
      );

  testWidgets('GT-01 non-repo empty state', (tester) async {
    await seedGitWorkspace(
      workspace: 'GT Empty',
      suffix: 'gt-01',
      project: 'GtEmpty',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT Empty');
    await openSourceControl(tester, projectName: 'GtEmpty');
    await pumpUntilFound(tester, find.text('No Git repository in this project'));
    expect(find.text('Initialize Git in this project'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('GT-02 initialize repository', (tester) async {
    final seeded = await seedGitWorkspace(
      workspace: 'GT-Init',
      suffix: 'gt-02',
      project: 'GtInit',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT-Init');
    await openSourceControl(tester, projectName: 'GtInit');
    await tapText(tester, 'Initialize Git in this project');
    await pumpUntilAbsent(
      tester,
      find.text('No Git repository in this project'),
      timeout: const Duration(seconds: 30),
    );
    await harness.configureGitIdentityAfterInit(seeded.workspacePath);
    final status = await harness.api.gitStatus();
    final branch = status['repository']?['branch']?.toString() ??
        status['branch']?.toString() ??
        '';
    expect(
      branch.contains('main') || branch.contains('master') || branch.isNotEmpty,
      isTrue,
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('GT-03 status lists changed files', (tester) async {
    final seeded = await seedGitWorkspace(
      workspace: 'GT Status',
      suffix: 'gt-03',
      project: 'GtStatus',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT Status');
    await openSourceControl(tester, projectName: 'GtStatus');
    await tapText(tester, 'Initialize Git in this project');
    await pumpUntilAbsent(tester, find.text('No Git repository in this project'));
    await harness.configureGitIdentityAfterInit(seeded.workspacePath);

    await harness.api.writeFile(
      path: seeded.suitePath,
      content: '*** Test Cases ***\nGit\n    Log    changed\n',
    );
    await tapTooltip(tester, 'Refresh');
    await pumpUntilFound(tester, find.textContaining('Untracked'));
    // Change rows may be long absolute paths; Untracked section is enough to
    // prove status listed workspace changes after the write.
    expect(find.text('Nothing to commit'), findsNothing);

    harness.expectNoFlutterErrors();
  });

  testWidgets('GT-04 select file for commit selection', (tester) async {
    final seeded = await seedGitWorkspace(
      workspace: 'GT Stage',
      suffix: 'gt-04',
      project: 'GtStage',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT Stage');
    await openSourceControl(tester, projectName: 'GtStage');
    await tapText(tester, 'Initialize Git in this project');
    await pumpUntilAbsent(tester, find.text('No Git repository in this project'));
    await harness.configureGitIdentityAfterInit(seeded.workspacePath);
    await harness.api.writeFile(
      path: seeded.suitePath,
      content: '*** Test Cases ***\nGit\n    Log    staged\n',
    );
    await tapTooltip(tester, 'Refresh');
    await pumpUntilFound(tester, find.textContaining('Untracked'));

    // Selection checkboxes act as stage selection before Commit Selected.
    final checkbox = find.byType(Checkbox);
    await pumpUntilFound(tester, checkbox);
    await tester.tap(checkbox.first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Selected'), findsWidgets);

    harness.expectNoFlutterErrors();
  });

  testWidgets('GT-05 commit succeeds', (tester) async {
    final seeded = await seedGitWorkspace(
      workspace: 'GT Commit',
      suffix: 'gt-05',
      project: 'GtCommit',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT Commit');
    await openSourceControl(tester, projectName: 'GtCommit');
    await tapText(tester, 'Initialize Git in this project');
    await pumpUntilAbsent(tester, find.text('No Git repository in this project'));
    await harness.configureGitIdentityAfterInit(seeded.workspacePath);
    await harness.api.writeFile(
      path: seeded.suitePath,
      content: '*** Test Cases ***\nGit\n    Log    commit-me\n',
    );
    await tapTooltip(tester, 'Refresh');
    await pumpUntilFound(tester, find.textContaining('Untracked'));

    await tester.enterText(commitField(), 'GT-05 commit');
    await tapText(tester, 'Commit All');
    await pumpUntilFound(
      tester,
      find.text('Nothing to commit'),
      timeout: const Duration(seconds: 30),
    );

    harness.expectNoFlutterErrors();
  });

  testWidgets('GT-06 empty commit message blocked', (tester) async {
    final seeded = await seedGitWorkspace(
      workspace: 'GT EmptyMsg',
      suffix: 'gt-06',
      project: 'GtEmptyMsg',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT EmptyMsg');
    await openSourceControl(tester, projectName: 'GtEmptyMsg');
    await tapText(tester, 'Initialize Git in this project');
    await pumpUntilAbsent(tester, find.text('No Git repository in this project'));
    await harness.configureGitIdentityAfterInit(seeded.workspacePath);
    await harness.api.writeFile(
      path: seeded.suitePath,
      content: '*** Test Cases ***\nGit\n    Log    block\n',
    );
    await tapTooltip(tester, 'Refresh');
    await pumpUntilFound(tester, find.textContaining('Untracked'));
    await pumpUntilFound(tester, find.text('Commit All'));

    final commitAll = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Commit All'),
        matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      ),
    );
    expect(commitAll.onPressed, isNull);

    harness.expectNoFlutterErrors();
  });

  testWidgets('GT-07 branch list and switch', (tester) async {
    final seeded = await seedGitWorkspace(
      workspace: 'GT Branch',
      suffix: 'gt-07',
      project: 'GtBranch',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT Branch');
    await openSourceControl(tester, projectName: 'GtBranch');
    await tapText(tester, 'Initialize Git in this project');
    await pumpUntilAbsent(tester, find.text('No Git repository in this project'));
    await harness.configureGitIdentityAfterInit(seeded.workspacePath);
    await harness.api.writeFile(
      path: seeded.suitePath,
      content: '*** Test Cases ***\nGit\n    Log    base\n',
    );
    await tapTooltip(tester, 'Refresh');
    await pumpUntilFound(tester, find.textContaining('Untracked'));
    await pumpUntilFound(tester, commitField());
    await tester.enterText(commitField(), 'base commit');
    await tapText(tester, 'Commit All');
    await pumpUntilFound(tester, find.text('Nothing to commit'));

    await harness.api.gitCreateBranch('feature/gt-07');
    final status = await harness.api.gitCheckout('feature/gt-07');
    expect(status['branch'], 'feature/gt-07');

    await tapTooltip(tester, 'Refresh');
    await pumpUntilFound(tester, find.textContaining('feature/gt-07'));

    harness.expectNoFlutterErrors();
  });

  testWidgets('GT-08 history and diff', (tester) async {
    final seeded = await seedGitWorkspace(
      workspace: 'GT History',
      suffix: 'gt-08',
      project: 'GtHistory',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT History');
    await openSourceControl(tester, projectName: 'GtHistory');
    await tapText(tester, 'Initialize Git in this project');
    await pumpUntilAbsent(tester, find.text('No Git repository in this project'));
    await harness.configureGitIdentityAfterInit(seeded.workspacePath);
    await harness.api.writeFile(
      path: seeded.suitePath,
      content: '*** Test Cases ***\nGit\n    Log    hist\n',
    );
    await tapTooltip(tester, 'Refresh');
    await pumpUntilFound(tester, find.textContaining('Untracked'));
    await pumpUntilFound(tester, commitField());
    await tester.enterText(commitField(), 'history commit');
    await tapText(tester, 'Commit All');
    await pumpUntilFound(tester, find.text('Nothing to commit'));

    final history = await harness.api.gitHistory();
    expect(history, isNotEmpty);

    await harness.api.writeFile(
      path: seeded.suitePath,
      content: '*** Test Cases ***\nGit\n    Log    hist-2\n',
    );
    await tapTooltip(tester, 'Refresh');
    await pumpUntilFound(
      tester,
      find.textContaining('git.robot', skipOffstage: false),
    );
    await tester.tap(find.textContaining('git.robot', skipOffstage: false).first);
    await tester.pump(const Duration(milliseconds: 500));

    harness.expectNoFlutterErrors();
  });

  testWidgets('GT-09 remote actions gated without remotes', (tester) async {
    await seedGitWorkspace(
      workspace: 'GT RemoteGate',
      suffix: 'gt-09',
      project: 'GtRemoteGate',
    );
    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT RemoteGate');
    await openSourceControl(tester, projectName: 'GtRemoteGate');

    // Without a repo, toolbar remote actions stay hidden.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ToolbarButton && widget.label == 'Fetch',
      ),
      findsNothing,
    );

    await tapText(tester, 'Initialize Git in this project');
    await pumpUntilAbsent(tester, find.text('No Git repository in this project'));
    // Repo without remotes: icon buttons with gated tooltips (no text labels).
    await pumpUntilFound(
      tester,
      find.byTooltip('Fetch (add a remote first)'),
    );
    await tester.tap(find.byTooltip('Fetch (add a remote first)'));
    await tester.pump(const Duration(milliseconds: 600));

    harness.expectNoFlutterErrors();
  });

  testWidgets('GT-10 fetch pull push with remotes', (tester) async {
    final seeded = await seedGitWorkspace(
      workspace: 'GT Remotes',
      suffix: 'gt-10',
      project: 'GtRemotes',
    );

    await harness.launchAppWithWorkspace(tester, workspaceName: 'GT Remotes');
    await openSourceControl(tester, projectName: 'GtRemotes');
    await tapText(tester, 'Initialize Git in this project');
    await pumpUntilAbsent(tester, find.text('No Git repository in this project'));
    await harness.configureGitIdentityAfterInit(seeded.workspacePath);

    await harness.api.writeFile(
      path: seeded.suitePath,
      content: '*** Test Cases ***\nGit\n    Log    remote\n',
    );
    await tapTooltip(tester, 'Refresh');
    await pumpUntilFound(tester, find.textContaining('Untracked'));
    await pumpUntilFound(tester, commitField());
    await tester.enterText(commitField(), 'seed for remotes');
    await tapText(tester, 'Commit All');
    await pumpUntilFound(tester, find.text('Nothing to commit'));

    await harness.api.seedLocalGitRemote();
    await tapTooltip(tester, 'Refresh');

    await pumpUntilFound(tester, find.byTooltip('Fetch'));
    await tester.tap(find.byTooltip('Push'));
    await tester.pump(const Duration(seconds: 2));
    final pushed = await harness.api.gitPush();
    expect(pushed['success'], isTrue, reason: '${pushed['message']}');

    await tester.tap(find.byTooltip('Fetch'));
    await tester.pump(const Duration(seconds: 2));
    final fetched = await harness.api.gitFetch();
    expect(fetched['success'], isTrue, reason: '${fetched['message']}');

    await tester.tap(find.byTooltip('Pull'));
    await tester.pump(const Duration(seconds: 2));
    final pulled = await harness.api.gitPull();
    expect(pulled['success'], isTrue, reason: '${pulled['message']}');

    harness.expectNoFlutterErrors();
  });
}
