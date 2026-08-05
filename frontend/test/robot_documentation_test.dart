import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/widgets/robot_documentation.dart';

void main() {
  testWidgets('renders every Robot doc block without truncating content', (
    tester,
  ) async {
    const documentation = '''
Summary with *bold*, _italic_, `code`, and \${variable}.

= Examples =
| Keyword | first |
| Keyword | second |

- First detail
- Second detail

1. Ordered detail

Final paragraph
continues on another line.
''';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SizedBox(
            width: 280,
            child: SingleChildScrollView(
              child: RobotDocumentation(documentation: documentation),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('robot-doc-heading')), findsOneWidget);
    expect(find.byKey(const Key('robot-doc-code')), findsOneWidget);
    expect(find.byKey(const Key('robot-doc-bullet')), findsNWidgets(2));
    expect(find.byKey(const Key('robot-doc-ordered')), findsOneWidget);

    final rendered = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
        .join('\n');

    for (final expected in [
      'Summary with bold, italic, code, and \${variable}.',
      'Examples',
      '| Keyword | first |',
      '| Keyword | second |',
      'First detail',
      'Second detail',
      'Ordered detail',
      'Final paragraph\ncontinues on another line.',
    ]) {
      expect(rendered, contains(expected));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a quiet empty state when libdoc has no text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: RobotDocumentation(documentation: '')),
      ),
    );

    expect(find.text('No documentation available.'), findsOneWidget);
  });
}
