import 'models/environment_info.dart';
import 'models/execution_info.dart';
import 'models/health_response.dart';
import 'models/package_info.dart';
import 'models/project_info.dart';
import 'models/workspace_info.dart';

export 'models/environment_info.dart';
export 'models/execution_info.dart';
export 'models/health_response.dart';
export 'models/package_info.dart';
export 'models/project_info.dart';
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
}

class GatewayException implements Exception {
  GatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}
