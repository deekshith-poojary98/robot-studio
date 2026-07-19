import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models/execution_info.dart';

/// Live execution log stream over WebSocket.
class ExecutionStreamClient {
  ExecutionStreamClient({
    this.url = 'ws://127.0.0.1:8765/api/v1/execution/stream',
  });

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
    _controller = StreamController<ExecutionStreamEvent>.broadcast();
    final socket = await WebSocket.connect(url);
    _socket = socket;
    _subscription = socket.listen(
      (message) {
        if (message is! String) return;
        try {
          final decoded = jsonDecode(message) as Map<String, dynamic>;
          _controller?.add(ExecutionStreamEvent.fromJson(decoded));
        } catch (_) {
          // Ignore malformed frames.
        }
      },
      onError: (Object error) {
        _controller?.addError(error);
      },
      onDone: () {
        _socket = null;
      },
      cancelOnError: false,
    );
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    await _controller?.close();
    _controller = null;
  }
}
