import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/index_info.dart';
import 'package:robot_studio/core/gateway/models/language_info.dart';
import 'package:robot_studio/presentation/editor/editor_navigation_widgets.dart';
import 'package:robot_studio/presentation/shell/controllers/editor_shell_controller.dart';

void main() {
  testWidgets('EditorHoverTooltip shows keyword args and docs', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EditorHoverTooltip(
            signature: SignatureHelpInfo(
              keyword: 'Open Workbook',
              documentation: 'Opens an Excel workbook.',
              libraryName: 'ExcelSage',
              parameters: [
                SignatureParameterInfo(
                  label: 'workbook_name: str',
                  name: 'workbook_name',
                  required: true,
                ),
                SignatureParameterInfo(
                  label: 'alias: str | None = None',
                  name: 'alias',
                  defaultValue: 'None',
                ),
              ],
              activeParameter: 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Open Workbook'), findsOneWidget);
    expect(find.text('ExcelSage'), findsOneWidget);
    expect(find.text('workbook_name: str'), findsOneWidget);
    expect(find.text('alias: str | None = None'), findsOneWidget);
    expect(find.text('Opens an Excel workbook.'), findsOneWidget);
  });

  testWidgets('long documentation is scrollable, not truncated', (
    tester,
  ) async {
    final docs = List.generate(
      40,
      (i) => 'Line $i of keyword docs.',
    ).join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: EditorHoverTooltip(
              signature: SignatureHelpInfo(
                keyword: 'Log',
                documentation: docs,
                libraryName: 'BuiltIn',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('Line 0 of keyword docs.'), findsOneWidget);
    expect(find.textContaining('Line 39 of keyword docs.'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('compact caret card keeps a short summary, not the full docs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EditorHoverTooltip(
            compact: true,
            signature: SignatureHelpInfo(
              keyword: 'remove_empty_rows',
              documentation:
                  'Remove empty rows from the sheet.\n\n'
                  'column_names_or_letters accepts headers or Excel letters. '
                  'This second paragraph must not appear while typing.',
              parameters: [
                SignatureParameterInfo(
                  label: 'output_filename',
                  name: 'output_filename',
                  required: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('remove_empty_rows'), findsOneWidget);
    expect(find.text('output_filename'), findsOneWidget);
    expect(
      find.textContaining('Remove empty rows from the sheet.'),
      findsOneWidget,
    );
    expect(find.textContaining('second paragraph'), findsNothing);
  });

  group('computeHoverTooltipPlacement', () {
    const tooltip = Size(200, 120);
    const viewport = Size(400, 300);
    const lineHeight = 20.0;
    const gap = 8.0;

    bool overlapsLine(
      HoverTooltipPlacement placement,
      double anchorY, {
      double height = 120,
    }) {
      final lineTop = (anchorY / lineHeight).floor() * lineHeight;
      final lineBottom = lineTop + lineHeight;
      final cardBottom = placement.top + height;
      return cardBottom > lineTop && placement.top < lineBottom;
    }

    test('places below when there is room', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(40, 40),
        viewport: viewport,
        tooltipSize: tooltip,
        lineHeight: lineHeight,
        gap: gap,
      );
      expect(placement.top, 40 + lineHeight + gap);
      expect(placement.left, 40 + 12);
      expect(overlapsLine(placement, 40), isFalse);
    });

    test('flips above near the bottom of the viewport', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(40, 250),
        viewport: viewport,
        tooltipSize: tooltip,
        lineHeight: lineHeight,
        gap: gap,
      );
      const lineTop = 240.0;
      expect(placement.top + tooltip.height, lessThanOrEqualTo(lineTop - gap));
      expect(overlapsLine(placement, 250), isFalse);
    });

    test('clears the full line when the anchor is mid-glyph', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(80, 255),
        viewport: viewport,
        tooltipSize: tooltip,
        lineHeight: lineHeight,
        gap: gap,
      );
      const lineTop = 240.0;
      expect(placement.top + tooltip.height, lessThanOrEqualTo(lineTop - gap));
      expect(overlapsLine(placement, 255), isFalse);
    });

    test('does not slide onto the line to stay in-viewport', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(40, 100),
        viewport: const Size(400, 120),
        tooltipSize: const Size(200, 80),
        lineHeight: lineHeight,
        gap: gap,
      );
      expect(placement.top + 80, lessThanOrEqualTo(100 - gap));
      expect(overlapsLine(placement, 100, height: 80), isFalse);
    });

    test('caret-driven card goes above, leaving room for the popup', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(40, 160),
        viewport: viewport,
        tooltipSize: tooltip,
        lineHeight: lineHeight,
        gap: gap,
        preferAbove: true,
      );
      const lineTop = 160.0;
      expect(placement.top + tooltip.height, lessThanOrEqualTo(lineTop - gap));
      expect(overlapsLine(placement, 160), isFalse);
    });

    test('uses the laid-out lineTop instead of snapping a stale Y', () {
      // Word wrap makes the true glyph row (200) sit above lineIndex ×
      // lineHeight (240). Without lineTop the card would hover over the
      // wrong block of code.
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(40, 250),
        viewport: const Size(400, 400),
        tooltipSize: const Size(200, 80),
        lineHeight: lineHeight,
        gap: gap,
        preferAbove: true,
        lineTop: 200,
      );
      expect(placement.top + 80, 200 - gap);
      final snapped = computeHoverTooltipPlacement(
        anchor: const Offset(40, 250),
        viewport: const Size(400, 400),
        tooltipSize: const Size(200, 80),
        lineHeight: lineHeight,
        gap: gap,
        preferAbove: true,
      );
      expect(snapped.top, isNot(placement.top));
    });

    test('preferAbove falls back below when there is no room above', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(40, 20),
        viewport: viewport,
        tooltipSize: tooltip,
        lineHeight: lineHeight,
        gap: gap,
        preferAbove: true,
      );
      expect(placement.top, 20 + lineHeight + gap);
    });

    test('shifts left near the right edge', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(350, 40),
        viewport: viewport,
        tooltipSize: tooltip,
        lineHeight: lineHeight,
      );
      expect(placement.left + tooltip.width, lessThanOrEqualTo(400 - 8));
      expect(placement.left, greaterThanOrEqualTo(8));
    });
  });

  test('parameter displayLabel falls back to name=default', () {
    const param = SignatureParameterInfo(
      label: '',
      name: 'browser',
      defaultValue: 'chrome',
    );
    expect(param.displayLabel, 'browser=chrome');
  });

  test('hover section details are not parsed as argument chips', () {
    expect(
      EditorShellController.argumentChipsFromHoverDetail('test cases'),
      isEmpty,
    );
    expect(
      EditorShellController.argumentChipsFromHoverDetail('test case'),
      isEmpty,
    );
    expect(
      EditorShellController.argumentChipsFromHoverDetail(r'${path}'),
      isNotEmpty,
    );
    expect(
      EditorShellController.argumentChipsFromHoverDetail(
        r'${username}, ${password}=secret',
      ),
      hasLength(2),
    );
    expect(
      EditorShellController.argumentChipsFromHoverDetail(
        'path: str = None, alias=None',
      ),
      isNotEmpty,
    );
  });

  test('SymbolKind test case label is singular', () {
    expect(SymbolKind.testCase.label, 'Test Case');
  });

  test('extractRobotTokenAt keeps multi-word keyword cells', () {
    const content = '''*** Test Cases ***
Demo
    Open Workbook    \${EXCEL_PATH}
''';
    final token = EditorShellController.extractRobotTokenAt(content, 3, 12);
    expect(token, 'Open Workbook');
  });
}
