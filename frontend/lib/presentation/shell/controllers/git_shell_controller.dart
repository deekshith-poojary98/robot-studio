import 'package:flutter/material.dart';

import '../../../core/gateway/transport_gateway.dart';
import 'shell_controller.dart';

/// Source-control state and Git operations owned by AppShell.
class GitShellController {
  GitShellController({
    required this.gateway,
    required this.notify,
    required this.isMounted,
    required this.appendLog,
    required this.showError,
    required this.workspace,
    required this.backendConnected,
  }) {
    commitController.addListener(notify);
  }

  final TransportGateway gateway;
  final ShellNotify notify;
  final ShellMounted isMounted;
  final void Function(String line) appendLog;
  final Future<void> Function(String title, Object error) showError;
  final WorkspaceInfo? Function() workspace;
  final bool Function() backendConnected;

  GitStatusInfo? status;
  List<GitBranchInfo> branches = [];
  List<GitCommitInfo> history = [];
  GitCommitInfo? selectedCommit;
  GitCommitDetailInfo? selectedCommitDetail;
  GitDiffInfo? diff;
  String? selectedDiffFile;
  final Set<String> selectedFiles = {};
  bool loading = false;
  bool busy = false;
  bool loadingHistory = false;
  bool loadingDiff = false;
  final TextEditingController commitController = TextEditingController();

  Map<String, GitFileStatus> get fileStatuses {
    final statuses = <String, GitFileStatus>{};
    for (final change in status?.changes ?? const []) {
      statuses[change.path] = change.status;
    }
    return statuses;
  }

  List<String> get localBranchNames => branches
      .where((branch) => !branch.remote)
      .map((branch) => branch.name)
      .toList();

  bool get isRepository => status?.repository.isRepository == true;

  String? get currentBranch => status?.repository.branch;

  void reset() {
    status = null;
    branches = [];
    history = [];
    selectedCommit = null;
    selectedCommitDetail = null;
    diff = null;
    selectedDiffFile = null;
    selectedFiles.clear();
    loading = false;
    busy = false;
    loadingHistory = false;
    loadingDiff = false;
    commitController.clear();
  }

  void dispose() {
    commitController.removeListener(notify);
    commitController.dispose();
  }

  Future<void> loadStatus() async {
    if (workspace() == null || !backendConnected()) {
      status = null;
      branches = [];
      loading = false;
      notify();
      return;
    }

    final initialLoad = status == null;
    if (initialLoad) {
      loading = true;
      notify();
    }
    try {
      final next = await gateway.getGitStatus();
      final nextBranches = next.repository.isRepository
          ? await gateway.getGitBranches()
          : <GitBranchInfo>[];
      if (!isMounted()) return;
      status = next;
      branches = nextBranches;
      loading = false;
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loading = false;
      notify();
      appendLog('[warn] Could not load git status: $error');
    }
  }

  Future<void> loadHistory() async {
    if (!isRepository) return;
    final initialLoad = history.isEmpty;
    if (initialLoad) {
      loadingHistory = true;
      notify();
    }
    try {
      final next = await gateway.getGitHistory(limit: 50);
      if (!isMounted()) return;
      history = next;
      loadingHistory = false;
      if (selectedCommit != null) {
        final match = next
            .where((item) => item.hash == selectedCommit!.hash)
            .toList();
        selectedCommit = match.isEmpty ? null : match.first;
      }
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loadingHistory = false;
      notify();
      appendLog('[warn] Could not load git history: $error');
    }
  }

  Future<void> loadDiff(String filePath) async {
    loadingDiff = true;
    selectedDiffFile = filePath;
    notify();
    try {
      final next = await gateway.getGitDiff(filePath: filePath);
      if (!isMounted()) return;
      diff = next;
      loadingDiff = false;
      notify();
    } catch (error) {
      if (!isMounted()) return;
      loadingDiff = false;
      notify();
      await showError('Git diff', error);
    }
  }

  Future<void> refresh() async {
    await loadStatus();
    if (isRepository) {
      await loadHistory();
    }
  }

  Future<void> initRepository() async {
    busy = true;
    notify();
    try {
      await gateway.initGitRepository();
      await refresh();
      appendLog('[info] Git repository initialized');
    } catch (error) {
      await showError('Initialize Git repository', error);
    } finally {
      if (isMounted()) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> commit({List<String>? files}) async {
    busy = true;
    notify();
    try {
      await gateway.commitGitChanges(
        message: commitController.text.trim(),
        files: files,
      );
      commitController.clear();
      selectedFiles.clear();
      selectedDiffFile = null;
      diff = null;
      await refresh();
      appendLog('[info] Git commit created');
    } catch (error) {
      await showError('Commit', error);
    } finally {
      if (isMounted()) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> checkout(String branch) async {
    busy = true;
    notify();
    try {
      await gateway.checkoutGitBranch(branch);
      await refresh();
      appendLog('[info] Checked out branch "$branch"');
    } catch (error) {
      await showError('Checkout branch', error);
    } finally {
      if (isMounted()) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> createBranch(String name) async {
    busy = true;
    notify();
    try {
      await gateway.createGitBranch(name);
      await refresh();
      appendLog('[info] Created branch "$name"');
    } catch (error) {
      await showError('Create branch', error);
    } finally {
      if (isMounted()) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> deleteBranch(String name) async {
    busy = true;
    notify();
    try {
      await gateway.deleteGitBranch(name);
      await refresh();
      appendLog('[info] Deleted branch "$name"');
    } catch (error) {
      await showError('Delete branch', error);
    } finally {
      if (isMounted()) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> runRemote(
    String action,
    Future<GitRemoteResultInfo> Function() call,
  ) async {
    busy = true;
    notify();
    try {
      final result = await call();
      if (!isMounted()) return;
      if (result.success) {
        await refresh();
        appendLog('[info] Git $action completed');
      } else {
        await showError('Git $action', result.message);
      }
    } catch (error) {
      await showError('Git $action', error);
    } finally {
      if (isMounted()) {
        busy = false;
        notify();
      }
    }
  }

  Future<bool> applyIdentity({
    required String name,
    required String email,
    required String scope,
  }) async {
    busy = true;
    notify();
    try {
      await gateway.setGitIdentity(name: name, email: email, scope: scope);
      await refresh();
      appendLog('[info] Git identity set to $name');
      return true;
    } catch (error) {
      await showError('Git identity', error);
      return false;
    } finally {
      if (isMounted()) {
        busy = false;
        notify();
      }
    }
  }

  Future<bool> addRemote({required String name, required String url}) async {
    busy = true;
    notify();
    try {
      await gateway.addGitRemote(name: name, url: url);
      await refresh();
      appendLog('[info] Git remote $name configured');
      return true;
    } catch (error) {
      await showError('Add remote', error);
      return false;
    } finally {
      if (isMounted()) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> selectCommit(GitCommitInfo commit) async {
    selectedCommit = commit;
    selectedDiffFile = null;
    diff = null;
    notify();
    try {
      final detail = await gateway.getGitCommitDetail(commit.hash);
      if (!isMounted()) return;
      selectedCommitDetail = detail;
      notify();
    } catch (error) {
      await showError('Commit details', error);
    }
  }

  void toggleFile(String path) {
    if (selectedFiles.contains(path)) {
      selectedFiles.remove(path);
    } else {
      selectedFiles.add(path);
    }
    notify();
  }
}
