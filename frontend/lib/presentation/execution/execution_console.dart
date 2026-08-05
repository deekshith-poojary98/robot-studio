import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class ExecutionConsole extends StatefulWidget {
  const ExecutionConsole({
    super.key,
    required this.lines,
    this.autoScroll = true,
  });

  final List<String> lines;
  final bool autoScroll;

  @override
  State<ExecutionConsole> createState() => _ExecutionConsoleState();
}

class _ExecutionConsoleState extends State<ExecutionConsole> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant ExecutionConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoScroll && widget.lines.length != oldWidget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        _controller.jumpTo(_controller.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return Center(
        child: Text(
          'Execution output will appear here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.lines.length,
      itemBuilder: (context, index) {
        final line = widget.lines[index];
        return Text(
          line,
          style: TextStyle(
            color: _colorFor(line),
            fontSize: 12,
            height: 1.45,
            fontFamily: 'Menlo',
          ),
        );
      },
    );
  }

  Color _colorFor(String line) {
    final upper = line.toUpperCase();
    if (upper.contains('| PASS |') || upper.contains('[PASS]')) {
      return context.palette.success;
    }
    if (upper.contains('| FAIL |') || upper.contains('[FAIL]')) {
      return context.palette.error;
    }
    if (upper.contains('| WARN |') || upper.contains('[WARN]')) {
      return context.palette.warning;
    }
    if (upper.contains('| INFO |') || upper.contains('[INFO]')) {
      return context.palette.info;
    }
    return context.palette.textSecondary;
  }
}
