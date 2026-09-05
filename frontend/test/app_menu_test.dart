import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/widgets/app_menu.dart';

void main() {
  testWidgets('checked popup rows stay at compact menu height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PopupMenuButton<String>(
            itemBuilder: (context) => [
              AppCheckedPopupMenuItem<String>(
                value: 'a',
                checked: true,
                child: const Text('connect-hr'),
              ),
              AppCheckedPopupMenuItem<String>(
                value: 'b',
                checked: false,
                child: const Text('OrangeHRM'),
              ),
            ],
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    Size itemSize(String label) {
      return tester.getSize(
        find.ancestor(
          of: find.text(label),
          matching: find.bySubtype<PopupMenuItem<String>>(),
        ),
      );
    }

    expect(itemSize('connect-hr').height, kAppMenuItemHeight);
    expect(itemSize('OrangeHRM').height, kAppMenuItemHeight);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
