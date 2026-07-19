class PackageInfo {
  const PackageInfo({
    required this.name,
    required this.version,
    this.latestVersion,
    this.summary,
    this.author,
    this.homepage,
    this.license,
    this.location,
    this.requires = const [],
    this.updateAvailable = false,
  });

  factory PackageInfo.fromJson(Map<String, dynamic> json) {
    return PackageInfo(
      name: json['name'] as String,
      version: json['version'] as String,
      latestVersion: json['latest_version'] as String?,
      summary: json['summary'] as String?,
      author: json['author'] as String?,
      homepage: json['homepage'] as String?,
      license: json['license'] as String?,
      location: json['location'] as String?,
      requires: (json['requires'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      updateAvailable: json['update_available'] as bool? ?? false,
    );
  }

  final String name;
  final String version;
  final String? latestVersion;
  final String? summary;
  final String? author;
  final String? homepage;
  final String? license;
  final String? location;
  final List<String> requires;
  final bool updateAvailable;
}

class PackageSearchResult {
  const PackageSearchResult({
    required this.name,
    required this.latestVersion,
    this.summary,
  });

  factory PackageSearchResult.fromJson(Map<String, dynamic> json) {
    return PackageSearchResult(
      name: json['name'] as String,
      latestVersion: (json['latest_version'] as String?) ?? '',
      summary: json['summary'] as String?,
    );
  }

  final String name;
  final String latestVersion;
  final String? summary;
}

class PackageVersionList {
  const PackageVersionList({
    required this.name,
    required this.versions,
    this.latestVersion,
  });

  factory PackageVersionList.fromJson(Map<String, dynamic> json) {
    return PackageVersionList(
      name: json['name'] as String,
      latestVersion: json['latest_version'] as String?,
      versions: (json['versions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  final String name;
  final String? latestVersion;
  final List<String> versions;
}

class PackageInstallSelection {
  const PackageInstallSelection({
    required this.name,
    required this.version,
    this.summary,
  });

  final String name;
  final String version;
  final String? summary;
}

class PackageListResult {
  const PackageListResult({
    required this.packages,
    required this.robotFrameworkInstalled,
    this.robotFrameworkVersion,
    this.environmentId,
    this.environmentName,
  });

  factory PackageListResult.fromJson(Map<String, dynamic> json) {
    final items = json['packages'] as List<dynamic>? ?? const [];
    return PackageListResult(
      packages: items
          .map((item) => PackageInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
      robotFrameworkInstalled:
          json['robot_framework_installed'] as bool? ?? false,
      robotFrameworkVersion: json['robot_framework_version'] as String?,
      environmentId: json['environment_id'] as String?,
      environmentName: json['environment_name'] as String?,
    );
  }

  final List<PackageInfo> packages;
  final bool robotFrameworkInstalled;
  final String? robotFrameworkVersion;
  final String? environmentId;
  final String? environmentName;
}

class PackageOperationResult {
  const PackageOperationResult({
    this.package,
    this.logs = const [],
    this.robotFrameworkInstalled = false,
    this.robotFrameworkVersion,
  });

  factory PackageOperationResult.fromJson(Map<String, dynamic> json) {
    final packageJson = json['package'];
    return PackageOperationResult(
      package: packageJson is Map<String, dynamic>
          ? PackageInfo.fromJson(packageJson)
          : null,
      logs: (json['logs'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      robotFrameworkInstalled:
          json['robot_framework_installed'] as bool? ?? false,
      robotFrameworkVersion: json['robot_framework_version'] as String?,
    );
  }

  final PackageInfo? package;
  final List<String> logs;
  final bool robotFrameworkInstalled;
  final String? robotFrameworkVersion;
}

enum PackageSort {
  name,
  version,
  update;

  String get apiValue => switch (this) {
        PackageSort.name => 'name',
        PackageSort.version => 'version',
        PackageSort.update => 'update',
      };

  String get label => switch (this) {
        PackageSort.name => 'Name',
        PackageSort.version => 'Version',
        PackageSort.update => 'Update Available',
      };
}
