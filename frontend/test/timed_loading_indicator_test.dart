import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/widgets/timed_loading_indicator.dart';

void main() {
  testWidgets('advances patience copy every interval', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: TimedLoadingIndicator(interval: Duration(seconds: 30)),
        ),
      ),
    );

    expect(find.text('Getting things ready…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Working on it…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Making progress…'), findsOneWidget);

    // Jump to the last message and confirm it sticks.
    for (var i = 0; i < TimedLoadingIndicator.messages.length; i++) {
      await tester.pump(const Duration(seconds: 30));
    }
    expect(find.text('Thanks for your patience…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Thanks for your patience…'), findsOneWidget);
  });
}
