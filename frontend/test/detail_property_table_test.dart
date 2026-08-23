import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/widgets/detail_property_table.dart';

void main() {
  testWidgets('DetailPropertyTable shows label and value columns', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: DetailPropertyTable(
            rows: [
              DetailPropertyRow(label: 'Python version', value: '3.13.9'),
              DetailPropertyRow(
                label: 'Location',
                value: '/tmp/project/.robotstudio/environments/venv',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Python version'), findsOneWidget);
    expect(find.text('3.13.9'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(
      find.text('/tmp/project/.robotstudio/environments/venv'),
      findsOneWidget,
    );
  });
}
