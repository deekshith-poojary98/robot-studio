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
class RobotTestRunGutter extends StatefulWidget {
  const RobotTestRunGutter({
    super.key,
    required this.notifier,
    required this.tests,
    this.scrollController,
    this.onRun,
    this.enabled = true,
    this.width = editorRunGutterWidth,
  });

  final CodeIndicatorValueNotifier notifier;
  final List<EditorRunnableTest> tests;
  final ScrollController? scrollController;
  final ValueChanged<EditorRunnableTest>? onRun;
  final bool enabled;
  final double width;

  @override
  State<RobotTestRunGutter> createState() => _RobotTestRunGutterState();
}

class _RobotTestRunGutterState extends State<RobotTestRunGutter> {
  CodeIndicatorValue? _geometry;
  double _geometryScrollOffset = 0;

  double get _scrollOffset {
    final controller = widget.scrollController;
    return controller != null && controller.hasClients ? controller.offset : 0;
  }

  @override
  void initState() {
    super.initState();
    _geometry = widget.notifier.value;
    _geometryScrollOffset = _scrollOffset;
    widget.notifier.addListener(_onGeometryChanged);
    widget.scrollController?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant RobotTestRunGutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notifier != oldWidget.notifier) {
      oldWidget.notifier.removeListener(_onGeometryChanged);
      widget.notifier.addListener(_onGeometryChanged);
      _geometry = widget.notifier.value;
      _geometryScrollOffset = _scrollOffset;
    }
    if (widget.scrollController != oldWidget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
      _geometryScrollOffset = _scrollOffset;
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onGeometryChanged);
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  void _onGeometryChanged() {
    if (!mounted) return;
    setState(() {
      _geometry = widget.notifier.value;
      _geometryScrollOffset = _scrollOffset;
    });
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final byLine = runnableTestsByLine(widget.tests);
    final paragraphs = _geometry?.paragraphs ?? const [];
    // Paragraph tops are relative to the scroll position at which re_editor
    // published them. Apply any newer scroll delta directly so Windows wheel
    // scrolling cannot leave this widget overlay behind the painted text.
    final scrollDelta = _scrollOffset - _geometryScrollOffset;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0.0;
        return SizedBox(
          width: widget.width,
          height: height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final row in paragraphs)
                if (byLine[row.index + 1] case final test?)
                  Positioned(
                    key: Key('run-test-gutter-${row.index + 1}'),
                    top: row.top - scrollDelta,
                    left: 0,
                    width: widget.width,
                    height: math.max(row.preferredLineHeight, 16),
                    child: _RunTestGutterButton(
                      name: test.name,
                      enabled: widget.enabled && widget.onRun != null,
                      onPressed: widget.onRun == null
                          ? null
                          : () => widget.onRun!(test),
                    ),
                  ),
            ],
          ),
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
