import 'models/environment_info.dart';
import 'models/file_info.dart';
import 'models/health_response.dart';
import 'models/index_info.dart';
import 'models/package_info.dart';
import 'models/project_info.dart';
import 'models/report_info.dart';
import 'models/workspace_info.dart';

export 'models/environment_info.dart';
export 'models/execution_info.dart';
export 'models/file_info.dart';
export 'models/health_response.dart';
export 'models/index_info.dart';
export 'models/package_info.dart';
export 'models/project_info.dart';
export 'models/report_info.dart';
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

  Future<ProjectInfo> createProject({
    required String name,
    required ProjectType type,
  });

  Future<ProjectInfo> importProject(String path);

  Future<List<ProjectInfo>> listProjects();

  Future<ProjectInfo> openProject(String projectId);

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

  Future<PackageInfo> getPackage(String name);

  Future<PackageOperationResult> installPackage(String name);

  Future<PackageOperationResult> updatePackage(String name);

  Future<PackageOperationResult> uninstallPackage(String name);

  Future<ExecutionInfo> runFile({String? file});

  Future<ExecutionInfo> runProject();

  Future<ExecutionInfo> stopExecution();

  Future<ExecutionStatusInfo> getExecutionStatus();

  Future<List<ExecutionInfo>> listExecutionHistory();

  Future<List<ExecutionInfo>> listReports();

  Future<ExecutionInfo> getReport(String runId);

  Future<void> deleteReport(String runId);

  Future<String> openReportLog(String runId);

  Future<String> openReportHtml(String runId);

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
  });

  Future<List<SymbolReferenceInfo>> languageReferences({
    String? name,
    String? symbolId,
    SymbolKind? kind,
  });

  Future<HoverInfo?> languageHover({
    String? name,
    String? symbolId,
    SymbolKind? kind,
  });

  Future<List<IndexedSymbolInfo>> documentSymbols(String filePath);

  Future<List<IndexedSymbolInfo>> workspaceSymbols({
    String query = '',
    int limit = 200,
  });

  Future<FileContentInfo> readFile(String path);

  Future<FileWriteResult> writeFile({
    required String path,
    required String content,
  });

  Future<List<FileTreeNode>> listFileTree({
    String? path,
    int depth = 3,
  });
}

class GatewayException implements Exception {
  GatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}
