import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/widgets/unsaved_changes_dialog.dart';

void main() {
  testWidgets('unsaved changes dialog returns Save', (tester) async {
    late UnsavedChangesChoice choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await showUnsavedChangesDialog(
                  context,
                  title: 'Unsaved Changes',
                  message: 'Save before leaving?',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(choice, UnsavedChangesChoice.save);
  });

  testWidgets('unsaved changes dialog returns Discard', (tester) async {
    late UnsavedChangesChoice choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await showUnsavedChangesDialog(
                  context,
                  title: 'Unsaved Settings',
                  message: 'Discard?',
                  discardLabel: 'Discard',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(choice, UnsavedChangesChoice.discard);
  });
}
