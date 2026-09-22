import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'update_check_config.dart';
import 'update_info.dart';

/// Fetches latest Robot Studio metadata from the update middleman.
///
/// Retries a few times so a Render free-tier cold start can finish waking up.
class UpdateCheckService {
  UpdateCheckService({
    http.Client? client,
    this.baseUrl = kUpdateServiceBaseUrl,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// [attempts] includes the first try (3 = try, retry, retry).
  Future<UpdateInfo> fetchLatest({
    String channel = 'stable',
    Duration timeout = const Duration(seconds: 45),
    int attempts = 3,
  }) async {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty) {
      throw StateError('Update service URL is not configured');
    }
    if (attempts < 1) {
      throw ArgumentError.value(attempts, 'attempts', 'must be >= 1');
    }

    final uri = Uri.parse('$root/v1/latest').replace(
      queryParameters: {
        if (_osQuery() != null) 'os': _osQuery()!,
        'channel': channel,
      },
    );

    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await _fetchOnce(uri, timeout: timeout);
      } on _PermanentUpdateFailure catch (error) {
        throw StateError(error.message);
      } catch (error) {
        lastError = error;
        if (attempt >= attempts) break;
        // Cold start: wait a bit longer between tries.
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }

    throw StateError(
      'Update check failed after $attempts attempts: $lastError',
    );
  }

  Future<UpdateInfo> _fetchOnce(Uri uri, {required Duration timeout}) async {
    final response = await _client.get(uri).timeout(timeout);

    if (response.statusCode == 404) {
      throw const _PermanentUpdateFailure('No releases published yet');
    }
    // Transient platform / gateway errors — worth retrying (Render wake, 502).
    if (response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504 ||
        response.statusCode == 429) {
      throw StateError(
        'Update service temporarily unavailable '
        '(HTTP ${response.statusCode})',
      );
    }
    if (response.statusCode >= 400) {
      throw _PermanentUpdateFailure(
        'Update check failed (HTTP ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const _PermanentUpdateFailure('Unexpected update response');
    }
    final info = UpdateInfo.fromJson(decoded);
    if (info.version.isEmpty) {
      throw const _PermanentUpdateFailure('Update response missing version');
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

class _PermanentUpdateFailure implements Exception {
  const _PermanentUpdateFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
