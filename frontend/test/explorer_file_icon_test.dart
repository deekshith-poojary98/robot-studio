import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/widgets/explorer_file_icon.dart';

void main() {
  testWidgets('explorerFileIcon renders SvgPicture for files and folders', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              explorerFileIcon(name: 'script.py'),
              explorerFileIcon(name: 'suite.robot'),
              explorerFileIcon(name: 'helpers.resource'),
              explorerFileIcon(name: 'tests', isDirectory: true),
              explorerFileIcon(
                name: 'resources',
                isDirectory: true,
                expanded: true,
              ),
              explorerFileIcon(name: 'src', isDirectory: true, loading: true),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SvgPicture), findsNWidgets(5));
    expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
  });
}
