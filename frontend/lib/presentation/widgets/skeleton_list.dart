import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Muted placeholder rows used while lists load — avoids spinner pop-in.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rows = 6,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.sm,
    ),
  });

  final int rows;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: rows,
      itemBuilder: (context, index) {
        final widthFactor = 0.45 + ((index % 3) * 0.15);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: context.palette.surfaceHover,
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: widthFactor.clamp(0.4, 0.9),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: context.palette.surfaceHover,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Cross-fade between loading skeleton and real content.
class FadeLoadSwitch extends StatelessWidget {
  const FadeLoadSwitch({
    super.key,
    required this.loading,
    required this.child,
    this.skeletonRows = 6,
  });

  final bool loading;
  final Widget child;
  final int skeletonRows;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: loading
          ? SkeletonList(key: const ValueKey('skeleton'), rows: skeletonRows)
          : KeyedSubtree(key: const ValueKey('content'), child: child),
    );
  }
}
