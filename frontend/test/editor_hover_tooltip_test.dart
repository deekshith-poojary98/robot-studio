import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
              parameters: [
                SignatureParameterInfo(label: 'workbook_name: str'),
                SignatureParameterInfo(label: 'alias: str | None = None'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Open Workbook'), findsOneWidget);
    expect(find.text('workbook_name: str'), findsOneWidget);
    expect(find.text('alias: str | None = None'), findsOneWidget);
    expect(find.text('Opens an Excel workbook.'), findsOneWidget);
  });

  test('extractRobotTokenAt keeps multi-word keyword cells', () {
    const content = '''*** Test Cases ***
Demo
    Open Workbook    \${EXCEL_PATH}
''';
    final token = EditorShellController.extractRobotTokenAt(
      content,
      3,
      12,
    );
    expect(token, 'Open Workbook');
  });
}
