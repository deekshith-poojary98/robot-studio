import 'package:package_info_plus/package_info_plus.dart';

/// Desktop app identity from the platform package (pubspec `version:`).
class AppInfo {
  const AppInfo({
    required this.version,
    required this.buildNumber,
    this.appName = 'Robot Studio',
  });

  final String appName;
  final String version;
  final String buildNumber;

  /// e.g. `1.1.0 (6)` when build is present, else just `1.1.0`.
  String get displayVersion {
    final build = buildNumber.trim();
    if (build.isEmpty || build == '0') return version;
    return '$version ($build)';
  }

  static AppInfo? _cached;

  /// Loads once per process. Safe to call from UI init.
  static Future<AppInfo> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final info = await PackageInfo.fromPlatform();
    final loaded = AppInfo(
      appName: info.appName.trim().isEmpty ? 'Robot Studio' : info.appName,
      version: info.version,
      buildNumber: info.buildNumber,
    );
    _cached = loaded;
    return loaded;
  }

  /// Test / preview override. Pass `null` to clear.
  static void debugSet(AppInfo? value) => _cached = value;
}
