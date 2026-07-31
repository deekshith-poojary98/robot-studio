import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/widgets/always_delayed_tooltip.dart';

void main() {
  testWidgets('always delayed tooltip waits on every hover target', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              AlwaysDelayedTooltip(
                message: 'path/a',
                waitDuration: Duration(milliseconds: 400),
                child: SizedBox(
                  key: Key('a'),
                  width: 80,
                  height: 40,
                  child: Text('A'),
                ),
              ),
              AlwaysDelayedTooltip(
                message: 'path/b',
                waitDuration: Duration(milliseconds: 400),
                child: SizedBox(
                  key: Key('b'),
                  width: 80,
                  height: 40,
                  child: Text('B'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    // First hover — must wait.
    await gesture.moveTo(tester.getCenter(find.byKey(const Key('a'))));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('path/a'), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('path/a'), findsOneWidget);

    // Immediate hop to sibling — must wait again (Material Tooltip would not).
    await gesture.moveTo(tester.getCenter(find.byKey(const Key('b'))));
    await tester.pump(); // exit A / enter B
    expect(find.text('path/a'), findsNothing);
    expect(find.text('path/b'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('path/b'), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('path/b'), findsOneWidget);
  });
}
