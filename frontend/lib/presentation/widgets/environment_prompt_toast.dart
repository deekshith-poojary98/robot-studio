import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Bottom-right dismissible toast for environment setup (does not push chrome).
class EnvironmentPromptToast extends StatefulWidget {
  const EnvironmentPromptToast({
    super.key,
    required this.title,
    required this.message,
    required this.actions,
    required this.onDismiss,
  });

  final String title;
  final String message;
  final List<EnvironmentPromptAction> actions;
  final VoidCallback onDismiss;

  @override
  State<EnvironmentPromptToast> createState() => _EnvironmentPromptToastState();
}

class EnvironmentPromptAction {
  const EnvironmentPromptAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;
}

class _EnvironmentPromptToastState extends State<EnvironmentPromptToast>
    with SingleTickerProviderStateMixin {
  static const double _actionHeight = 32;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0.15, 0.35),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  double _maxWidth(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - 32;
    return available < 400 ? available.clamp(240.0, 400.0) : 400.0;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 56,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _maxWidth(context),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.memory_outlined,
                              size: 18,
                              color: AppColors.warning,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.message,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Dismiss',
                            onPressed: () => unawaited(_dismiss()),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            iconSize: 18,
                            color: AppColors.textMuted,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Wrap so narrow windows stack the actions instead of clipping.
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final action in widget.actions)
                            _ActionButton(
                              action: action,
                              height: _actionHeight,
                              onPressed: () {
                                action.onPressed();
                                unawaited(_dismiss());
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.height,
    required this.onPressed,
  });

  final EnvironmentPromptAction action;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      action.label,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: action.primary ? FontWeight.w600 : FontWeight.w500,
        height: 1.2,
      ),
    );

    if (action.primary) {
      return SizedBox(
        height: height,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: Size(0, height),
            maximumSize: Size(double.infinity, height),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
          ),
          child: label,
        ),
      );
    }

    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size(0, height),
          maximumSize: Size(double.infinity, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          foregroundColor: AppColors.textSecondary,
        ),
        child: label,
      ),
    );
  }
}
