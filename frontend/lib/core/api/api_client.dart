import '../gateway/rest_transport_gateway.dart';
import '../gateway/transport_gateway.dart';

export '../gateway/models/environment_info.dart';
export '../gateway/models/execution_info.dart';
export '../gateway/models/health_response.dart';
export '../gateway/models/package_info.dart';
export '../gateway/models/project_info.dart';
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
  }) =>
      _gateway.createWorkspace(name: name, location: location);

  @override
  Future<WorkspaceInfo> openWorkspace(String path) =>
      _gateway.openWorkspace(path);

  @override
  Future<List<WorkspaceInfo>> listRecentWorkspaces() =>
      _gateway.listRecentWorkspaces();

  @override
  Future<ProjectInfo> createProject({
    required String name,
    required ProjectType type,
  }) =>
      _gateway.createProject(name: name, type: type);

  @override
  Future<ProjectInfo> importProject(String path) =>
      _gateway.importProject(path);

  @override
  Future<List<ProjectInfo>> listProjects() => _gateway.listProjects();

  @override
  Future<ProjectInfo> openProject(String projectId) =>
      _gateway.openProject(projectId);

  @override
  Future<List<ProjectInfo>> listRecentProjects() =>
      _gateway.listRecentProjects();

  @override
  Future<List<EnvironmentInfo>> listEnvironments({
    EnvironmentSort sort = EnvironmentSort.active,
  }) =>
      _gateway.listEnvironments(sort: sort);

  @override
  Future<EnvironmentInfo> createEnvironment({
    required String name,
    required String pythonInterpreter,
    bool installRobotFramework = false,
  }) =>
      _gateway.createEnvironment(
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
  }) =>
      _gateway.cloneEnvironment(
        environmentId: environmentId,
        name: name,
      );

  @override
  Future<void> deleteEnvironment({
    required String environmentId,
    bool deleteFiles = false,
  }) =>
      _gateway.deleteEnvironment(
        environmentId: environmentId,
        deleteFiles: deleteFiles,
      );

  @override
  Future<PackageListResult> listPackages({
    String? query,
    PackageSort sort = PackageSort.name,
  }) =>
      _gateway.listPackages(query: query, sort: sort);

  @override
  Future<List<PackageSearchResult>> searchPackages(String query) =>
      _gateway.searchPackages(query);

  @override
  Future<PackageInfo> getPackage(String name) => _gateway.getPackage(name);

  @override
  Future<PackageOperationResult> installPackage(String name) =>
      _gateway.installPackage(name);

  @override
  Future<PackageOperationResult> updatePackage(String name) =>
      _gateway.updatePackage(name);

  @override
  Future<PackageOperationResult> uninstallPackage(String name) =>
      _gateway.uninstallPackage(name);

  @override
  Future<ExecutionInfo> runFile({String? file}) => _gateway.runFile(file: file);

  @override
  Future<ExecutionInfo> runProject() => _gateway.runProject();

  @override
  Future<ExecutionInfo> stopExecution() => _gateway.stopExecution();

  @override
  Future<ExecutionStatusInfo> getExecutionStatus() =>
      _gateway.getExecutionStatus();

  @override
  Future<List<ExecutionInfo>> listExecutionHistory() =>
      _gateway.listExecutionHistory();
}

/// Backward-compatible alias for [GatewayException].
typedef ApiException = GatewayException;
