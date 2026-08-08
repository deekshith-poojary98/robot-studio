import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/language_info.dart';
import 'package:robot_studio/core/gateway/models/library_info.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/editor/editor_syntax.dart';
import 'package:robot_studio/presentation/editor/robot_language.dart';
import 'package:robot_studio/presentation/libraries/library_explorer_controller.dart';
import 'package:robot_studio/presentation/libraries/library_explorer_panel.dart';

List<String> _runsWithColor(InlineSpan root, Color color) {
  final runs = <String>[];
  void walk(InlineSpan node) {
    if (node is TextSpan) {
      if (node.style?.color == color && (node.text?.isNotEmpty ?? false)) {
        runs.add(node.text!);
      }
      for (final child in node.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(root);
  return runs;
}

void main() {
  test('typed libdoc args vs Robot variable forms', () {
    expect(argumentHighlightLanguage('name: str'), 'typed');
    expect(argumentHighlightLanguage('path: str | None = None'), 'typed');
    expect(argumentHighlightLanguage('*varargs'), 'typed');
    expect(argumentHighlightLanguage(r'${path}'), 'robot');
    expect(argumentHighlightLanguage(r'@{args}'), 'robot');
  });

  test('typed args color names, custom types, literals, and defaults', () {
    final palette = AppPalette.dark;
    final theme = robotHighlightTheme(Brightness.dark);
    final span = highlightKeywordArgument(
      'locator: WebElement | str | list[Locator] = shot-{index}.png',
      palette,
    );

    expect(
      span.toPlainText(),
      'locator: WebElement | str | list[Locator] = shot-{index}.png',
    );

    final typeColor = theme['built_in']!.color!;
    final nameColor = theme['variable']!.color!;
    final literalColor = theme['keyword']!.color!;
    final stringColor = theme['string']!.color!;

    expect(_runsWithColor(span, nameColor), contains('locator'));
    expect(
      _runsWithColor(span, typeColor),
      containsAll(['WebElement', 'str', 'list', 'Locator']),
    );
    expect(_runsWithColor(span, stringColor), contains('shot-{index}.png'));

    final noneSpan = highlightKeywordArgument(
      'path: str | None = None',
      palette,
    );
    expect(_runsWithColor(noneSpan, literalColor), contains('None'));
  });

  testWidgets('keyword Arguments use editor syntax colors', (tester) async {
    final controller = LibraryExplorerController(
      listLibraries: () async => [
        const LibraryInfo(name: 'Browser', keywordCount: 1),
      ],
      getLibrary: (name) async => LibraryInfo(
        name: name,
        keywordCount: 1,
        keywords: const [
          LibraryKeywordInfo(
            name: 'Capture Element Screenshot',
            documentation: 'Captures a screenshot.',
            parameters: [
              SignatureParameterInfo(
                label:
                    'locator: WebElement | str | list[WebElement | str | list[Locator]]',
                name: 'locator',
                required: true,
              ),
              SignatureParameterInfo(
                label:
                    'filename: str = selenium-element-screenshot-{index}.png',
                name: 'filename',
                defaultValue: 'selenium-element-screenshot-{index}.png',
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: LibraryExplorerPanel(
              hasProject: true,
              controller: controller,
              onJumpToSource: (_, __) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Browser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capture Element Screenshot'));
    await tester.pumpAndSettle();

    expect(find.text('Arguments'), findsOneWidget);

    final theme = robotHighlightTheme(Brightness.dark);
    final typeColor = theme['built_in']!.color!;
    final stringColor = theme['string']!.color!;

    var sawWebElement = false;
    var sawDefault = false;
    for (final widget in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      final root = widget.textSpan;
      if (root == null) continue;
      final plain = root.toPlainText();
      if (plain.contains('WebElement')) {
        expect(_runsWithColor(root, typeColor), contains('WebElement'));
        sawWebElement = true;
      }
      if (plain.contains('selenium-element-screenshot')) {
        expect(
          _runsWithColor(root, stringColor).join(),
          contains('selenium-element-screenshot'),
        );
        sawDefault = true;
      }
    }
    expect(sawWebElement, isTrue);
    expect(sawDefault, isTrue);
  });
}
