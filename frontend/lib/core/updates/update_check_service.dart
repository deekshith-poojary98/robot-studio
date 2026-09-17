import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'update_check_config.dart';
import 'update_info.dart';

/// Fetches latest Robot Studio metadata from the update middleman.
class UpdateCheckService {
  UpdateCheckService({
    http.Client? client,
    this.baseUrl = kUpdateServiceBaseUrl,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<UpdateInfo> fetchLatest({
    String channel = 'stable',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty) {
      throw StateError('Update service URL is not configured');
    }

    final uri = Uri.parse('$root/v1/latest').replace(
      queryParameters: {
        if (_osQuery() != null) 'os': _osQuery()!,
        'channel': channel,
      },
    );

    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode == 404) {
      throw StateError('No releases published yet');
    }
    if (response.statusCode >= 400) {
      throw StateError(
        'Update check failed (HTTP ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected update response');
    }
    final info = UpdateInfo.fromJson(decoded);
    if (info.version.isEmpty) {
      throw StateError('Update response missing version');
    }
    return info;
  }

  static String? _osQuery() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return null;
  }
}
