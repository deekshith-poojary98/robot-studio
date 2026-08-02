import 'models/doctor_info.dart';
import 'models/environment_info.dart';
import 'models/file_info.dart';
import 'models/git_info.dart';
import 'models/health_response.dart';
import 'models/index_info.dart';
import 'models/language_info.dart';
import 'models/package_info.dart';
import 'models/plugin_info.dart';
import 'models/project_info.dart';
import 'models/report_info.dart';
import 'models/test_explorer_info.dart';
import 'models/workspace_info.dart';

export 'models/doctor_info.dart';
export 'models/environment_info.dart';
export 'models/execution_info.dart';
export 'models/file_info.dart';
export 'models/git_info.dart';
export 'models/health_response.dart';
export 'models/index_info.dart';
export 'models/language_info.dart';
export 'models/package_info.dart';
export 'models/plugin_info.dart';
export 'models/project_info.dart';
export 'models/report_info.dart';
export 'models/test_explorer_info.dart';
export 'models/workspace_info.dart';

/// Abstraction over REST, gRPC, or other transport mechanisms.
abstract class TransportGateway {
  Future<HealthResponse> health();

  Future<WorkspaceInfo> createWorkspace({
    required String name,
    required String location,
  });

  Future<WorkspaceInfo> openWorkspace(String path);

  Future<List<WorkspaceInfo>> listRecentWorkspaces();

  Future<ProjectInfo> createProject({required String name});

  Future<ProjectInfo> importProject(String path);

  Future<List<ProjectInfo>> listProjects();

  Future<ProjectInfo> openProject(String projectId);

  Future<OpenProjectByPathResult> openProjectByPath(
    String path, {
    bool force = false,
  });

  Future<OpenProjectByPathResult> createStandaloneProject({
    required String name,
    required String location,
  });

  Future<List<ProjectInfo>> listRecentProjects();

  Future<List<EnvironmentInfo>> listEnvironments({
    EnvironmentSort sort = EnvironmentSort.active,
  });

  Future<List<PythonInterpreterInfo>> listPythonInterpreters();

  Future<EnvironmentInfo> createEnvironment({
    required String name,
    required String pythonInterpreter,
    bool installRobotFramework = false,
  });

  Future<EnvironmentInfo> importEnvironment(String path);

  Future<EnvironmentInfo> activateEnvironment(String environmentId);

  Future<EnvironmentInfo> getEnvironment(String environmentId);

  Future<EnvironmentInfo> cloneEnvironment({
    required String environmentId,
    required String name,
  });

  Future<void> deleteEnvironment({
    required String environmentId,
    bool deleteFiles = false,
  });

  Future<PackageListResult> listPackages({
    String? query,
    PackageSort sort = PackageSort.name,
  });

  Future<List<PackageSearchResult>> searchPackages(String query);

  Future<PackageVersionList> listPackageVersions(String name);

  Future<PackageInfo> getPackage(String name);

  Future<PackageOperationResult> installPackage(String name, {String? version});

  Future<PackageOperationResult> updatePackage(String name);

  Future<PackageOperationResult> uninstallPackage(String name);

  Future<ExecutionInfo> runFile({String? file});

  Future<ExecutionInfo> runProject();

  Future<TestNodeInfo> getTestTree({String? query, bool lazy = true});

  Future<int> countTests({String? tag, bool projectWide = false});

  Future<List<TestNodeInfo>> getTestsForFile(String path);

  Future<ExecutionInfo> runTest({required String file, required String name});

  Future<ExecutionInfo> runTestSuite({String? file});

  Future<ExecutionInfo> runTestsByTag(String tag);

  Future<ExecutionInfo> runFailedTests();

  Future<ExecutionInfo> runSelectedTests(
    List<({String file, String name})> tests,
  );

  Future<ExecutionInfo> stopExecution();

  Future<ExecutionStatusInfo> getExecutionStatus();

  Future<List<ExecutionInfo>> listExecutionHistory();

  Future<List<ExecutionInfo>> listReports();

  Future<ExecutionInfo> getReport(String runId);

  Future<void> deleteReport(String runId);

  Future<String> openReportLog(String runId);

  Future<String> openReportHtml(String runId);

  Future<String> openReportXml(String runId);

  Future<String> revealReport(String runId);

  Future<DashboardSummary> getReportsDashboard();

  Future<IndexStatusInfo> rebuildIndex();

  Future<IndexStatusInfo> getIndexStatus();

  Future<List<IndexedSymbolInfo>> searchSymbols({
    String query = '',
    SymbolKind? kind,
    int limit = 100,
  });

  Future<IndexedSymbolInfo?> languageDefinition({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  });

  Future<List<SymbolReferenceInfo>> languageReferences({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  });

  Future<HoverInfo?> languageHover({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  });

  Future<List<IndexedSymbolInfo>> documentSymbols(String filePath);

  Future<List<IndexedSymbolInfo>> workspaceSymbols({
    String query = '',
    int limit = 200,
  });

  Future<List<CompletionItemInfo>> languageCompletion({
    required String filePath,
    required int line,
    required int column,
    required String content,
    String query = '',
  });

  Future<List<DiagnosticInfo>> languageDiagnostics({
    required String filePath,
    required String content,
  });

  Future<String> languageFormat({
    required String filePath,
    required String content,
    int? startLine,
    int? endLine,
  });

  Future<SignatureHelpInfo?> languageSignatureHelp({
    required String filePath,
    required int line,
    required int column,
    required String content,
  });

  Future<FileContentInfo> readFile(String path);

  Future<FileWriteResult> writeFile({
    required String path,
    required String content,
  });

  Future<FileMutationResult> createFile({
    required String path,
    String content = '',
  });

  Future<FileMutationResult> createDirectory({required String path});

  Future<FileMutationResult> renamePath({
    required String path,
    required String newName,
  });

  Future<FileMutationResult> movePath({
    required String path,
    required String destinationDir,
  });

  Future<FileMutationResult> duplicatePath({required String path});

  Future<FileMutationResult> deletePath({required String path});

  Future<List<FileTreeNode>> listFileTree({String? path, int depth = 0});

  Future<List<PluginInfo>> listPlugins();

  Future<List<PluginInfo>> refreshPlugins();

  Future<PluginInfo?> getPlugin(String id);

  Future<PluginInfo> enablePlugin(String id);

  Future<PluginInfo> disablePlugin(String id);

  Future<PluginInfo> reloadPlugin(String id);

  Future<GitStatusInfo> getGitStatus();

  Future<GitRepositoryInfo> initGitRepository();

  Future<GitRepositoryInfo?> refreshGitRepository();

  Future<List<GitCommitInfo>> getGitHistory({int limit = 50});

  Future<GitCommitDetailInfo> getGitCommitDetail(String commitHash);

  Future<List<GitBranchInfo>> getGitBranches();

  Future<GitRepositoryInfo> checkoutGitBranch(String branch);

  Future<GitBranchInfo> createGitBranch(String name, {String? startPoint});

  Future<void> deleteGitBranch(String name);

  Future<GitCommitInfo> commitGitChanges({
    required String message,
    List<String>? files,
  });

  Future<GitRemoteResultInfo> fetchGit();

  Future<GitRemoteResultInfo> pullGit();

  Future<GitRemoteResultInfo> pushGit();

  Future<GitDiffInfo> getGitDiff({String? filePath, String? commit});

  Future<DoctorProfilesBundle> getDoctorProfiles();

  Future<DoctorReport> runDoctor({
    String profile = 'default',
    String? projectId,
    List<String>? providerIds,
  });

  Future<DoctorReport> getDoctorReport(String reportId);

  Future<List<DoctorReportSummary>> getDoctorHistory({
    String? projectId,
    int limit = 20,
  });
}

class GatewayException implements Exception {
  GatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}
