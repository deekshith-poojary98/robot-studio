import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/backend_config.dart';
import '../logging/app_logger.dart';
import 'models/execution_info.dart';

/// Live execution log stream over WebSocket.
class ExecutionStreamClient {
  ExecutionStreamClient({String? url})
      : url = url ?? BackendConfig.wsExecutionUrl;

  final String url;
  WebSocket? _socket;
  StreamController<ExecutionStreamEvent>? _controller;
  StreamSubscription<dynamic>? _subscription;

  Stream<ExecutionStreamEvent> get events {
    final controller = _controller;
    if (controller == null) {
      throw StateError('ExecutionStreamClient is not connected');
    }
    return controller.stream;
  }

  bool get isConnected => _socket != null;

  Future<void> connect() async {
    if (_socket != null) return;
    AppLogger.info('Connecting execution stream', tag: 'Stream', data: url);
    _controller = StreamController<ExecutionStreamEvent>.broadcast();
    try {
      final socket = await WebSocket.connect(url);
      _socket = socket;
      _subscription = socket.listen(
        (message) {
          if (message is! String) return;
          try {
            final decoded = jsonDecode(message) as Map<String, dynamic>;
            final event = ExecutionStreamEvent.fromJson(decoded);
            if (event.type != 'output') {
              AppLogger.debug(
                'stream event type=${event.type}',
                tag: 'Stream',
                data: {
                  'runId': event.runId,
                  'status': event.status,
                  'message': event.message,
                  'exitCode': event.exitCode,
                },
              );
            }
            _controller?.add(event);
          } catch (error) {
            AppLogger.warn(
              'Ignoring malformed stream frame',
              tag: 'Stream',
              error: error,
            );
          }
        },
        onError: (Object error) {
          AppLogger.error(
            'Execution stream error',
            tag: 'Stream',
            error: error,
          );
          _controller?.addError(error);
        },
        onDone: () {
          AppLogger.info('Execution stream closed', tag: 'Stream');
          _socket = null;
        },
        cancelOnError: false,
      );
      AppLogger.info('Execution stream connected', tag: 'Stream');
    } catch (error, stackTrace) {
      AppLogger.error(
        'Execution stream connect failed',
        tag: 'Stream',
        error: error,
        stackTrace: stackTrace,
      );
      await _controller?.close();
      _controller = null;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    AppLogger.debug('Disconnecting execution stream', tag: 'Stream');
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    await _controller?.close();
    _controller = null;
  }
}
