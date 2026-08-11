import '../gateway/rest_transport_gateway.dart';
import '../gateway/transport_gateway.dart';

export '../gateway/models/environment_info.dart';
export '../gateway/models/execution_info.dart';
export '../gateway/models/health_response.dart';
export '../gateway/models/package_info.dart';
export '../gateway/models/project_info.dart';
export '../gateway/models/report_info.dart';
export '../gateway/models/test_explorer_info.dart';
export '../gateway/models/index_info.dart';
export '../gateway/models/file_info.dart';
export '../gateway/models/workspace_info.dart';
export '../gateway/rest_transport_gateway.dart';
export '../gateway/transport_gateway.dart';

/// Backward-compatible alias for [RestTransportGateway].
class ApiClient implements TransportGateway {
  ApiClient({String? baseUrl, RestTransportGateway? gateway})
    : _gateway = gateway ?? RestTransportGateway(baseUrl: baseUrl);

  final TransportGateway _gateway;

  @override
  Future<HealthResponse> health() => _gateway.health();

  @override
  Future<WorkspaceInfo> createWorkspace({
    required String name,
    required String location,
  }) => _gateway.createWorkspace(name: name, location: location);

  @override
  Future<WorkspaceInfo> openWorkspace(String path) =>
      _gateway.openWorkspace(path);

  @override
  Future<List<WorkspaceInfo>> listRecentWorkspaces() =>
      _gateway.listRecentWorkspaces();

  @override
  Future<ProjectInfo> createProject({required String name}) =>
      _gateway.createProject(name: name);

  @override
  Future<ProjectInfo> importProject(String path) =>
      _gateway.importProject(path);

  @override
  Future<List<ProjectInfo>> listProjects() => _gateway.listProjects();

  @override
  Future<ProjectInfo> openProject(String projectId) =>
      _gateway.openProject(projectId);

  @override
  Future<OpenProjectByPathResult> openProjectByPath(
    String path, {
    bool force = false,
  }) => _gateway.openProjectByPath(path, force: force);

  @override
  Future<OpenProjectByPathResult> createStandaloneProject({
    required String name,
    required String location,
  }) => _gateway.createStandaloneProject(name: name, location: location);

  @override
  Future<List<ProjectInfo>> listRecentProjects() =>
      _gateway.listRecentProjects();

  @override
  Future<List<EnvironmentInfo>> listEnvironments({
    EnvironmentSort sort = EnvironmentSort.active,
  }) => _gateway.listEnvironments(sort: sort);

  @override
  Future<List<PythonInterpreterInfo>> listPythonInterpreters() =>
      _gateway.listPythonInterpreters();

  @override
  Future<EnvironmentInfo> createEnvironment({
    required String name,
    required String pythonInterpreter,
    bool installRobotFramework = false,
  }) => _gateway.createEnvironment(
    name: name,
    pythonInterpreter: pythonInterpreter,
    installRobotFramework: installRobotFramework,
  );

  @override
  Future<EnvironmentInfo> importEnvironment(String path) =>
      _gateway.importEnvironment(path);

  @override
  Future<EnvironmentInfo> activateEnvironment(String environmentId) =>
      _gateway.activateEnvironment(environmentId);

  @override
  Future<EnvironmentInfo> getEnvironment(String environmentId) =>
      _gateway.getEnvironment(environmentId);

  @override
  Future<EnvironmentInfo> cloneEnvironment({
    required String environmentId,
    required String name,
  }) => _gateway.cloneEnvironment(environmentId: environmentId, name: name);

  @override
  Future<void> deleteEnvironment({
    required String environmentId,
    bool deleteFiles = false,
  }) => _gateway.deleteEnvironment(
    environmentId: environmentId,
    deleteFiles: deleteFiles,
  );

  @override
  Future<PackageListResult> listPackages({
    String? query,
    PackageSort sort = PackageSort.name,
  }) => _gateway.listPackages(query: query, sort: sort);

  @override
  Future<List<PackageSearchResult>> searchPackages(String query) =>
      _gateway.searchPackages(query);

  @override
  Future<PackageVersionList> listPackageVersions(String name) =>
      _gateway.listPackageVersions(name);

  @override
  Future<PackageInfo> getPackage(String name) => _gateway.getPackage(name);

  @override
  Future<PackageOperationResult> installPackage(
    String name, {
    String? version,
    bool force = false,
  }) => _gateway.installPackage(name, version: version, force: force);

  @override
  Future<PackageOperationResult> installRequirements(String filePath) =>
      _gateway.installRequirements(filePath);

  @override
  Future<PackageOperationResult> exportRequirements(String filePath) =>
      _gateway.exportRequirements(filePath);

  @override
  Future<PackageOperationResult> updatePackage(String name) =>
      _gateway.updatePackage(name);

  @override
  Future<PackageOperationResult> uninstallPackage(String name) =>
      _gateway.uninstallPackage(name);

  @override
  Future<ExecutionInfo> runFile({String? file, String? configurationId}) =>
      _gateway.runFile(file: file, configurationId: configurationId);

  @override
  Future<ExecutionInfo> runProject({
    bool confirm = false,
    String? configurationId,
  }) => _gateway.runProject(confirm: confirm, configurationId: configurationId);

  @override
  Future<TestNodeInfo> getTestTree({String? query, bool lazy = true}) =>
      _gateway.getTestTree(query: query, lazy: lazy);

  @override
  Future<int> countTests({String? tag, bool projectWide = false}) =>
      _gateway.countTests(tag: tag, projectWide: projectWide);

  @override
  Future<List<TestNodeInfo>> getTestsForFile(String path) =>
      _gateway.getTestsForFile(path);

  @override
  Future<ExecutionInfo> runTest({
    required String file,
    required String name,
    String? configurationId,
  }) => _gateway.runTest(
    file: file,
    name: name,
    configurationId: configurationId,
  );

  @override
  Future<ExecutionInfo> runTestSuite({
    String? file,
    bool confirm = false,
    String? configurationId,
  }) => _gateway.runTestSuite(
    file: file,
    confirm: confirm,
    configurationId: configurationId,
  );

  @override
  Future<ExecutionInfo> runTestsByTag(
    String tag, {
    bool confirm = false,
    String? configurationId,
  }) => _gateway.runTestsByTag(
    tag,
    confirm: confirm,
    configurationId: configurationId,
  );

  @override
  Future<ExecutionInfo> runFailedTests({String? configurationId}) =>
      _gateway.runFailedTests(configurationId: configurationId);

  @override
  Future<ExecutionInfo> runSelectedTests(
    List<({String file, String name})> tests, {
    String? configurationId,
  }) => _gateway.runSelectedTests(tests, configurationId: configurationId);

  @override
  Future<ExecutionInfo> stopExecution() => _gateway.stopExecution();

  @override
  Future<ExecutionStatusInfo> getExecutionStatus() =>
      _gateway.getExecutionStatus();

  @override
  Future<List<ExecutionInfo>> listExecutionHistory() =>
      _gateway.listExecutionHistory();

  @override
  Future<List<ExecutionInfo>> listReports() => _gateway.listReports();

  @override
  Future<ExecutionInfo> getReport(String runId) => _gateway.getReport(runId);

  @override
  Future<void> deleteReport(String runId) => _gateway.deleteReport(runId);

  @override
  Future<String> openReportLog(String runId) => _gateway.openReportLog(runId);

  @override
  Future<String> openReportHtml(String runId) => _gateway.openReportHtml(runId);

  @override
  Future<String> openReportXml(String runId) => _gateway.openReportXml(runId);

  @override
  Future<String> revealReport(String runId) => _gateway.revealReport(runId);

  @override
  Future<DashboardSummary> getReportsDashboard() =>
      _gateway.getReportsDashboard();

  @override
  Future<IndexStatusInfo> rebuildIndex() => _gateway.rebuildIndex();

  @override
  Future<IndexStatusInfo> getIndexStatus() => _gateway.getIndexStatus();

  @override
  Future<InsightsInfo> getInsights() => _gateway.getInsights();

  @override
  Future<List<IndexedSymbolInfo>> searchSymbols({
    String query = '',
    SymbolKind? kind,
    int limit = 100,
  }) => _gateway.searchSymbols(query: query, kind: kind, limit: limit);

  @override
  Future<ContentSearchResultInfo> searchContent({
    String query = '',
    int limit = 500,
    int contextLines = 1,
  }) => _gateway.searchContent(
    query: query,
    limit: limit,
    contextLines: contextLines,
  );

  @override
  Future<RunFailuresInfo> getRunFailures(String runId) =>
      _gateway.getRunFailures(runId);

  @override
  Future<IndexedSymbolInfo?> languageDefinition({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  }) => _gateway.languageDefinition(
    name: name,
    symbolId: symbolId,
    kind: kind,
    filePath: filePath,
    line: line,
    column: column,
    content: content,
  );

  @override
  Future<List<SymbolReferenceInfo>> languageReferences({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  }) => _gateway.languageReferences(
    name: name,
    symbolId: symbolId,
    kind: kind,
    filePath: filePath,
    line: line,
    column: column,
    content: content,
  );

  @override
  Future<HoverInfo?> languageHover({
    String? name,
    String? symbolId,
    SymbolKind? kind,
    String? filePath,
    int? line,
    int? column,
    String? content,
  }) => _gateway.languageHover(
    name: name,
    symbolId: symbolId,
    kind: kind,
    filePath: filePath,
    line: line,
    column: column,
    content: content,
  );

  @override
  Future<List<IndexedSymbolInfo>> documentSymbols(String filePath) =>
      _gateway.documentSymbols(filePath);

  @override
  Future<DocumentAnalysisInfo> analyzeDocument({
    required String filePath,
    required String content,
  }) => _gateway.analyzeDocument(filePath: filePath, content: content);

  @override
  Future<List<IndexedSymbolInfo>> workspaceSymbols({
    String query = '',
    int limit = 200,
  }) => _gateway.workspaceSymbols(query: query, limit: limit);

  @override
  Future<List<CompletionItemInfo>> languageCompletion({
    required String filePath,
    required int line,
    required int column,
    required String content,
    String query = '',
  }) => _gateway.languageCompletion(
    filePath: filePath,
    line: line,
    column: column,
    content: content,
    query: query,
  );

  @override
  Future<void> languageCompletionUsage({
    required String label,
    String kind = '',
  }) => _gateway.languageCompletionUsage(label: label, kind: kind);

  @override
  Future<List<DiagnosticInfo>> languageDiagnostics({
    required String filePath,
    required String content,
  }) => _gateway.languageDiagnostics(filePath: filePath, content: content);

  @override
  Future<String> languageFormat({
    required String filePath,
    required String content,
    int? startLine,
    int? endLine,
  }) => _gateway.languageFormat(
    filePath: filePath,
    content: content,
    startLine: startLine,
    endLine: endLine,
  );

  @override
  Future<SignatureHelpInfo?> languageSignatureHelp({
    required String filePath,
    required int line,
    required int column,
    required String content,
  }) => _gateway.languageSignatureHelp(
    filePath: filePath,
    line: line,
    column: column,
    content: content,
  );

  @override
  Future<List<LibraryInfo>> languageLibraries() => _gateway.languageLibraries();

  @override
  Future<LibraryInfo?> languageLibrary(String name) =>
      _gateway.languageLibrary(name);

  @override
  Future<List<PluginInfo>> listPlugins() => _gateway.listPlugins();

  @override
  Future<List<PluginInfo>> refreshPlugins() => _gateway.refreshPlugins();

  @override
  Future<PluginInfo?> getPlugin(String id) => _gateway.getPlugin(id);

  @override
  Future<PluginInfo> enablePlugin(String id) => _gateway.enablePlugin(id);

  @override
  Future<PluginInfo> disablePlugin(String id) => _gateway.disablePlugin(id);

  @override
  Future<PluginInfo> reloadPlugin(String id) => _gateway.reloadPlugin(id);

  @override
  Future<GitStatusInfo> getGitStatus() => _gateway.getGitStatus();

  @override
  Future<GitRepositoryInfo> initGitRepository() => _gateway.initGitRepository();

  @override
  Future<GitRepositoryInfo?> refreshGitRepository() =>
      _gateway.refreshGitRepository();

  @override
  Future<List<GitCommitInfo>> getGitHistory({int limit = 50}) =>
      _gateway.getGitHistory(limit: limit);

  @override
  Future<GitCommitDetailInfo> getGitCommitDetail(String commitHash) =>
      _gateway.getGitCommitDetail(commitHash);

  @override
  Future<List<GitBranchInfo>> getGitBranches() => _gateway.getGitBranches();

  @override
  Future<GitRepositoryInfo> checkoutGitBranch(String branch) =>
      _gateway.checkoutGitBranch(branch);

  @override
  Future<GitBranchInfo> createGitBranch(String name, {String? startPoint}) =>
      _gateway.createGitBranch(name, startPoint: startPoint);

  @override
  Future<void> deleteGitBranch(String name) => _gateway.deleteGitBranch(name);

  @override
  Future<GitCommitInfo> commitGitChanges({
    required String message,
    List<String>? files,
  }) => _gateway.commitGitChanges(message: message, files: files);

  @override
  Future<GitRemoteResultInfo> fetchGit() => _gateway.fetchGit();

  @override
  Future<GitRemoteResultInfo> pullGit() => _gateway.pullGit();

  @override
  Future<GitRemoteResultInfo> pushGit() => _gateway.pushGit();

  @override
  Future<List<GitRemoteInfo>> listGitRemotes() => _gateway.listGitRemotes();

  @override
  Future<List<GitRemoteInfo>> addGitRemote({
    String name = 'origin',
    required String url,
  }) => _gateway.addGitRemote(name: name, url: url);

  @override
  Future<GitIdentityInfo> getGitIdentity() => _gateway.getGitIdentity();

  @override
  Future<GitIdentityInfo> setGitIdentity({
    required String name,
    required String email,
    String scope = 'local',
  }) => _gateway.setGitIdentity(name: name, email: email, scope: scope);

  @override
  Future<GitDiffInfo> getGitDiff({String? filePath, String? commit}) =>
      _gateway.getGitDiff(filePath: filePath, commit: commit);

  @override
  Future<DoctorProfilesBundle> getDoctorProfiles() =>
      _gateway.getDoctorProfiles();

  @override
  Future<DoctorReport> runDoctor({
    String profile = 'default',
    String? projectId,
    List<String>? providerIds,
  }) => _gateway.runDoctor(
    profile: profile,
    projectId: projectId,
    providerIds: providerIds,
  );

  @override
  Future<DoctorReport> getDoctorReport(String reportId) =>
      _gateway.getDoctorReport(reportId);

  @override
  Future<List<DoctorReportSummary>> getDoctorHistory({
    String? projectId,
    int limit = 20,
  }) => _gateway.getDoctorHistory(projectId: projectId, limit: limit);

  @override
  Future<RunConfigurationListInfo> listRunConfigurations() =>
      _gateway.listRunConfigurations();

  @override
  Future<RunConfigurationInfo> createRunConfiguration(
    RunConfigurationDraft draft,
  ) => _gateway.createRunConfiguration(draft);

  @override
  Future<RunConfigurationInfo> updateRunConfiguration(
    String configurationId,
    RunConfigurationDraft draft,
  ) => _gateway.updateRunConfiguration(configurationId, draft);

  @override
  Future<void> deleteRunConfiguration(String configurationId) =>
      _gateway.deleteRunConfiguration(configurationId);

  @override
  Future<RunConfigurationInfo> duplicateRunConfiguration(
    String configurationId,
  ) => _gateway.duplicateRunConfiguration(configurationId);

  @override
  Future<String?> activateRunConfiguration(String? configurationId) =>
      _gateway.activateRunConfiguration(configurationId);

  @override
  Future<FileContentInfo> readFile(String path) => _gateway.readFile(path);

  @override
  Future<FileWriteResult> writeFile({
    required String path,
    required String content,
  }) => _gateway.writeFile(path: path, content: content);

  @override
  Future<FileMutationResult> createFile({
    required String path,
    String content = '',
  }) => _gateway.createFile(path: path, content: content);

  @override
  Future<FileMutationResult> createDirectory({required String path}) =>
      _gateway.createDirectory(path: path);

  @override
  Future<FileMutationResult> renamePath({
    required String path,
    required String newName,
  }) => _gateway.renamePath(path: path, newName: newName);

  @override
  Future<FileMutationResult> movePath({
    required String path,
    required String destinationDir,
  }) => _gateway.movePath(path: path, destinationDir: destinationDir);

  @override
  Future<FileMutationResult> duplicatePath({required String path}) =>
      _gateway.duplicatePath(path: path);

  @override
  Future<FileMutationResult> deletePath({required String path}) =>
      _gateway.deletePath(path: path);

  @override
  Future<List<FileTreeNode>> listFileTree({String? path, int depth = 0}) =>
      _gateway.listFileTree(path: path, depth: depth);

  @override
  Future<AppSettings> getSettings() => _gateway.getSettings();

  @override
  Future<AppSettings> updateSettings(Map<String, dynamic> patch) =>
      _gateway.updateSettings(patch);

  @override
  Future<AppSettings> resetSettings() => _gateway.resetSettings();
}

/// Backward-compatible alias for [GatewayException].
typedef ApiException = GatewayException;
