import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/gateway/models/index_info.dart';
import '../../core/gateway/models/language_info.dart';
import '../../core/theme/app_theme.dart';

/// Width of the play-control column left of the line numbers.
const double editorRunGutterWidth = AppSpacing.lg;

/// A Robot test/task the gutter can launch (`--test` / `--task` by name).
class EditorRunnableTest {
  const EditorRunnableTest({
    required this.line,
    required this.endLine,
    required this.name,
  });

  /// 1-based start line of the test case header.
  final int line;
  final int endLine;
  final String name;

  bool containsLine(int line) => line >= this.line && line <= endLine;
}

/// Test Cases / Tasks in a `.robot` outline. Keywords and Python stay out.
List<EditorRunnableTest> runnableTestsFromOutline(
  DocumentSymbolNode? root, {
  String? filePath,
}) {
  if (root == null) return const [];
  if (filePath != null && !filePath.toLowerCase().endsWith('.robot')) {
    return const [];
  }
  return [
    for (final node in root.walk())
      if (node.kind == SymbolKind.testCase)
        EditorRunnableTest(
          line: node.line,
          endLine: node.endLine ?? node.line,
          name: node.name,
        ),
  ];
}

EditorRunnableTest? enclosingRunnableTest(
  List<EditorRunnableTest> tests,
  int line,
) {
  EditorRunnableTest? best;
  for (final test in tests) {
    if (!test.containsLine(line)) continue;
    if (best == null || test.line >= best.line) best = test;
  }
  return best;
}

Map<int, EditorRunnableTest> runnableTestsByLine(
  List<EditorRunnableTest> tests,
) {
  return {for (final test in tests) test.line: test};
}

/// Play control on each visible test-case row — VS Code-style run-this-test.
class RobotTestRunGutter extends StatelessWidget {
  const RobotTestRunGutter({
    super.key,
    required this.notifier,
    required this.tests,
    this.onRun,
    this.enabled = true,
    this.width = editorRunGutterWidth,
  });

  final CodeIndicatorValueNotifier notifier;
  final List<EditorRunnableTest> tests;
  final ValueChanged<EditorRunnableTest>? onRun;
  final bool enabled;
  final double width;

  @override
  Widget build(BuildContext context) {
    final byLine = runnableTestsByLine(tests);
    return ValueListenableBuilder<CodeIndicatorValue?>(
      valueListenable: notifier,
      builder: (context, value, _) {
        final paragraphs = value?.paragraphs ?? const [];
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 0.0;
            return SizedBox(
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (final row in paragraphs)
                    if (byLine[row.index + 1] case final test?)
                      Positioned(
                        key: Key('run-test-gutter-${row.index + 1}'),
                        top: row.top,
                        left: 0,
                        width: width,
                        height: math.max(row.preferredLineHeight, 16),
                        child: _RunTestGutterButton(
                          name: test.name,
                          enabled: enabled && onRun != null,
                          onPressed: onRun == null ? null : () => onRun!(test),
                        ),
                      ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RunTestGutterButton extends StatefulWidget {
  const _RunTestGutterButton({
    required this.name,
    required this.enabled,
    this.onPressed,
  });

  final String name;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  State<_RunTestGutterButton> createState() => _RunTestGutterButtonState();
}

class _RunTestGutterButtonState extends State<_RunTestGutterButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.enabled && widget.onPressed != null;
    final color = !enabled
        ? palette.textMuted.withValues(alpha: 0.45)
        : _hover
        ? palette.success
        : palette.textMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Run ${widget.name}',
      child: Tooltip(
        message: 'Run ${widget.name}',
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          onEnter: enabled ? (_) => setState(() => _hover = true) : null,
          onExit: (_) => setState(() => _hover = false),
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: enabled ? widget.onPressed : null,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Icon(Icons.play_arrow, size: 13, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
