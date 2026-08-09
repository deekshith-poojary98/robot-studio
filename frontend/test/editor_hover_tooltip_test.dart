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

  group('computeHoverTooltipPlacement', () {
    const tooltip = Size(200, 120);
    const viewport = Size(400, 300);

    test('places below when there is room', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(40, 40),
        viewport: viewport,
        tooltipSize: tooltip,
        lineHeight: 20,
        gap: 4,
      );
      expect(placement.top, 40 + 20 + 4);
      expect(placement.left, 40 + 12);
    });

    test('flips above near the bottom of the viewport', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(40, 250),
        viewport: viewport,
        tooltipSize: tooltip,
        lineHeight: 20,
        gap: 4,
      );
      expect(placement.top, lessThan(250));
      expect(placement.top + tooltip.height, lessThanOrEqualTo(250));
    });

    test('shifts left near the right edge', () {
      final placement = computeHoverTooltipPlacement(
        anchor: const Offset(350, 40),
        viewport: viewport,
        tooltipSize: tooltip,
        lineHeight: 20,
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
