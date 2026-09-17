/// Payload from `GET /v1/latest` on the update middleman.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    required this.tag,
    required this.channel,
    this.releasedAt,
    this.notesUrl,
    this.downloadUrl,
    this.assetName,
    this.mandatory = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: (json['version'] as String? ?? '').trim(),
      build: (json['build'] as num?)?.toInt() ?? 0,
      tag: (json['tag'] as String? ?? '').trim(),
      channel: (json['channel'] as String? ?? 'stable').trim(),
      releasedAt: json['released_at'] as String?,
      notesUrl: json['notes_url'] as String?,
      downloadUrl: json['download_url'] as String?,
      assetName: json['asset_name'] as String?,
      mandatory: json['mandatory'] as bool? ?? false,
    );
  }

  final String version;
  final int build;
  final String tag;
  final String channel;
  final String? releasedAt;
  final String? notesUrl;
  final String? downloadUrl;
  final String? assetName;
  final bool mandatory;

  String get displayVersion {
    if (build <= 0) return version;
    return '$version ($build)';
  }
}

/// Compare `a` to `b`. Positive if [a] is newer.
int compareAppVersions({
  required String aVersion,
  required int aBuild,
  required String bVersion,
  required int bBuild,
}) {
  final a = _parseSemver(aVersion);
  final b = _parseSemver(bVersion);
  for (var i = 0; i < 3; i++) {
    final delta = a[i] - b[i];
    if (delta != 0) return delta;
  }
  return aBuild - bBuild;
}

bool isUpdateNewer({
  required UpdateInfo latest,
  required String currentVersion,
  required String currentBuild,
}) {
  final build = int.tryParse(currentBuild.trim()) ?? 0;
  return compareAppVersions(
        aVersion: latest.version,
        aBuild: latest.build,
        bVersion: currentVersion,
        bBuild: build,
      ) >
      0;
}

List<int> _parseSemver(String raw) {
  var value = raw.trim();
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  if (value.contains('+')) {
    value = value.split('+').first;
  }
  final parts = value.split('.');
  int part(int index) {
    if (index >= parts.length) return 0;
    return int.tryParse(parts[index].replaceAll(RegExp(r'[^0-9].*$'), '')) ??
        0;
  }

  return [part(0), part(1), part(2)];
}
