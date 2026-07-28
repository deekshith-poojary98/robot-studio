import 'package:flutter/material.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';

class EditorBreadcrumbBar extends StatelessWidget {
  const EditorBreadcrumbBar({
    super.key,
    required this.breadcrumb,
  });

  final EditorBreadcrumbInfo breadcrumb;

  @override
  Widget build(BuildContext context) {
    final segments = <String?>[
      breadcrumb.workspace,
      breadcrumb.project,
      breadcrumb.folder,
      breadcrumb.fileName,
      breadcrumb.symbol?.name,
    ].whereType<String>().where((item) => item.isNotEmpty).toList();

    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right, size: 14, color: AppColors.textMuted),
              ),
            Text(
              segments[i],
              style: TextStyle(
                fontSize: 11,
                color: i == segments.length - 1
                    ? AppColors.textPrimary
                    : AppColors.textMuted,
                fontWeight:
                    i == segments.length - 1 ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SignatureHelpOverlay extends StatelessWidget {
  const SignatureHelpOverlay({
    super.key,
    required this.signature,
  });

  final SignatureHelpInfo signature;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                signature.keyword,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              if (signature.parameters.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < signature.parameters.length; i++)
                      _ParameterChip(
                        parameter: signature.parameters[i],
                        active: i == signature.activeParameter,
                      ),
                  ],
                ),
              ],
              if (signature.documentation.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  signature.documentation,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ParameterChip extends StatelessWidget {
  const _ParameterChip({
    required this.parameter,
    required this.active,
  });

  final SignatureParameterInfo parameter;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? AppColors.accentSoft : AppColors.rail,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active ? AppColors.accent : AppColors.borderSubtle,
        ),
      ),
      child: Text(
        parameter.documentation.isEmpty
            ? parameter.label
            : '${parameter.label} (${parameter.documentation})',
        style: TextStyle(
          fontSize: 11,
          color: active ? AppColors.textPrimary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class PeekDefinitionPanel extends StatelessWidget {
  const PeekDefinitionPanel({
    super.key,
    required this.symbol,
    required this.onOpen,
    required onClose,
  }) : _onClose = onClose;

  final IndexedSymbolInfo symbol;
  final VoidCallback onOpen;
  final VoidCallback _onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                const Text('Peek Definition', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  tooltip: 'Open',
                  onPressed: onOpen,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('${symbol.kind.label}: ${symbol.name}'),
                Text(
                  symbol.locationLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (symbol.documentation.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(symbol.documentation),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
