import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/backend_config.dart';
import '../logging/app_logger.dart';
import 'models/workspace_event_info.dart';

/// Live workspace filesystem / domain event stream over WebSocket.
class WorkspaceEventStreamClient {
  WorkspaceEventStreamClient({String? url})
      : url = url ?? BackendConfig.wsWorkspaceEventsUrl;

  final String url;
  WebSocket? _socket;
  StreamController<WorkspaceStreamEvent>? _controller;
  StreamSubscription<dynamic>? _subscription;

  Stream<WorkspaceStreamEvent> get events {
    final controller = _controller;
    if (controller == null) {
      throw StateError('WorkspaceEventStreamClient is not connected');
    }
    return controller.stream;
  }

  bool get isConnected => _socket != null;

  Future<void> connect() async {
    if (_socket != null) return;
    AppLogger.info('Connecting workspace events', tag: 'LiveWS', data: url);
    _controller = StreamController<WorkspaceStreamEvent>.broadcast();
    try {
      final socket = await WebSocket.connect(url);
      _socket = socket;
      _subscription = socket.listen(
        (message) {
          if (message is! String) return;
          try {
            final decoded = jsonDecode(message) as Map<String, dynamic>;
            final event = WorkspaceStreamEvent.fromJson(decoded);
            if (event.type != 'connected') {
              AppLogger.debug(
                'workspace event type=${event.type}',
                tag: 'LiveWS',
                data: {
                  'path': event.path,
                  'reason': event.reason,
                  'scope': event.scope,
                },
              );
            }
            _controller?.add(event);
          } catch (error) {
            AppLogger.warn(
              'Ignoring malformed workspace event frame',
              tag: 'LiveWS',
              error: error,
            );
          }
        },
        onError: (Object error) {
          AppLogger.error(
            'Workspace event stream error',
            tag: 'LiveWS',
            error: error,
          );
          _controller?.addError(error);
        },
        onDone: () {
          AppLogger.info('Workspace event stream closed', tag: 'LiveWS');
          _socket = null;
        },
        cancelOnError: false,
      );
      AppLogger.info('Workspace event stream connected', tag: 'LiveWS');
    } catch (error, stackTrace) {
      AppLogger.error(
        'Workspace event stream connect failed',
        tag: 'LiveWS',
        error: error,
        stackTrace: stackTrace,
      );
      await _controller?.close();
      _controller = null;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    AppLogger.debug('Disconnecting workspace events', tag: 'LiveWS');
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    await _controller?.close();
    _controller = null;
  }
}
