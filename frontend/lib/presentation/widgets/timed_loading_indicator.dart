import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Centered spinner with patience copy that advances every [interval].
///
/// After the last message, the copy stays put until the parent removes this
/// widget (load finished or failed).
class TimedLoadingIndicator extends StatefulWidget {
  const TimedLoadingIndicator({
    super.key,
    this.interval = const Duration(seconds: 30),
    this.spinnerSize = 22,
    this.strokeWidth = 2,
    this.compact = false,
  });

  /// How long each message stays before the next one.
  final Duration interval;

  final double spinnerSize;
  final double strokeWidth;

  /// Tighter layout for strips / overlays (smaller gap and text).
  final bool compact;

  static const List<String> messages = [
    'Getting things ready…',
    'Working on it…',
    'Making progress…',
    'Still working…',
    'Taking a little more time…',
    'Putting everything together…',
    'Finishing up…',
    'Almost there…',
    'Just a little longer…',
    'Thanks for your patience…',
  ];

  @override
  State<TimedLoadingIndicator> createState() => _TimedLoadingIndicatorState();
}

class _TimedLoadingIndicatorState extends State<TimedLoadingIndicator> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void didUpdateWidget(TimedLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) {
      _timer?.cancel();
      _index = 0;
      _armTimer();
    }
  }

  void _armTimer() {
    if (TimedLoadingIndicator.messages.length <= 1) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      if (_index >= TimedLoadingIndicator.messages.length - 1) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      setState(() => _index += 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final message = TimedLoadingIndicator
        .messages[_index.clamp(0, TimedLoadingIndicator.messages.length - 1)];
    final gap = widget.compact ? AppSpacing.sm : AppSpacing.md;
    final textStyle =
        (widget.compact
                ? Theme.of(context).textTheme.bodySmall
                : Theme.of(context).textTheme.bodyMedium)
            ?.copyWith(color: palette.textSecondary);

    return Semantics(
      liveRegion: true,
      label: message,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(
            widget.compact ? AppSpacing.sm : AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: widget.spinnerSize,
                height: widget.spinnerSize,
                child: CircularProgressIndicator(
                  strokeWidth: widget.strokeWidth,
                ),
              ),
              SizedBox(height: gap),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    message,
                    key: ValueKey<int>(_index),
                    textAlign: TextAlign.center,
                    style: textStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
