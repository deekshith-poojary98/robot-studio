import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Two-column property/value table for detail panels (environments, packages).
class DetailPropertyTable extends StatelessWidget {
  const DetailPropertyTable({super.key, required this.rows});

  final List<DetailPropertyRow> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final borderSide = BorderSide(color: palette.border);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: palette.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Table(
          columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          border: TableBorder(horizontalInside: borderSide),
          children: [
            for (var i = 0; i < rows.length; i++)
              TableRow(
                decoration: BoxDecoration(
                  color: i.isEven ? palette.surface : palette.surfaceElevated,
                ),
                children: [
                  _PropertyLabelCell(label: rows[i].label),
                  _PropertyValueCell(value: rows[i].value),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class DetailPropertyRow {
  const DetailPropertyRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _PropertyLabelCell extends StatelessWidget {
  const _PropertyLabelCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.palette.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PropertyValueCell extends StatelessWidget {
  const _PropertyValueCell({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: SelectableText(
        value,
        style: TextStyle(
          color: context.palette.textPrimary,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}
