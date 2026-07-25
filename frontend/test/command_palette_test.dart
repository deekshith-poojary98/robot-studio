import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/search/command_palette.dart';

void main() {
  testWidgets('filters commands and activates selection', (tester) async {
    var ran = false;
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showCommandPalette(
                  context: context,
                  commands: [
                    PaletteItem(
                      id: 'run',
                      title: 'Run Project',
                      kind: PaletteItemKind.command,
                      keywords: const ['execute'],
                      onSelect: () => ran = true,
                    ),
                    PaletteItem(
                      id: 'env',
                      title: 'Manage Environments',
                      kind: PaletteItemKind.command,
                      onSelect: () {},
                    ),
                  ],
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

    expect(find.text('Run Project'), findsOneWidget);
    expect(find.text('Manage Environments'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'run');
    await tester.pumpAndSettle();

    expect(find.text('Run Project'), findsOneWidget);
    expect(find.text('Manage Environments'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(ran, isTrue);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('workspace search merges file results', (tester) async {
    var opened = false;
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showCommandPalette(
                  context: context,
                  commands: const [],
                  searchWorkspace: (query) async => [
                    PaletteItem(
                      id: 'file',
                      title: 'demo.robot',
                      subtitle: '/tmp/$query/demo.robot',
                      kind: PaletteItemKind.file,
                      onSelect: () => opened = true,
                    ),
                  ],
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

    await tester.enterText(find.byType(TextField), 'demo');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('demo.robot'), findsOneWidget);
    await tester.tap(find.text('demo.robot'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });
}
