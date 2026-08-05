import 'package:flutter/foundation.dart';

import '../gateway/transport_gateway.dart';
import '../logging/app_logger.dart';

/// Frontend mirror of backend SettingsService — single owner of live prefs.
///
/// Components must not read preference files; they listen to this notifier.
class AppSettingsController extends ChangeNotifier {
  AppSettingsController({required this.gateway});

  final TransportGateway gateway;

  AppSettings _settings = const AppSettings();
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  AppSettings get settings => _settings;
  EditorSettings get editor => _settings.editor;
  ExecutionSettings get execution => _settings.execution;
  SearchSettings get search => _settings.search;
  AppearanceSettings get appearance => _settings.appearance;
  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _settings = await gateway.getSettings();
      _loaded = true;
    } catch (error) {
      _error = '$error';
      AppLogger.debug('Settings load failed', tag: 'Settings', data: '$error');
      // Keep defaults so the IDE still works offline.
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> update(AppSettings next) async {
    final previous = _settings;
    _settings = next;
    notifyListeners();
    try {
      _settings = await gateway.updateSettings(next.toJson());
      _error = null;
      notifyListeners();
    } catch (error) {
      _settings = previous;
      _error = '$error';
      notifyListeners();
      AppLogger.debug('Settings update failed', tag: 'Settings', data: '$error');
      rethrow;
    }
  }

  Future<void> patch(Map<String, dynamic> patch) async {
    final previous = _settings;
    try {
      _settings = await gateway.updateSettings(patch);
      _error = null;
      notifyListeners();
    } catch (error) {
      _settings = previous;
      _error = '$error';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reset() async {
    _settings = await gateway.resetSettings();
    _error = null;
    notifyListeners();
  }
}
