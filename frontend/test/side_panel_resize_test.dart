import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/panels/side_panel.dart';
import 'package:robot_studio/presentation/sidebar/sidebar_panel.dart';
import 'package:robot_studio/presentation/widgets/side_panel_resize_handle.dart';

void main() {
  testWidgets('side panel resize handle reports drag deltas', (tester) async {
    final deltas = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SidePanel(
                panel: SidebarPanel.explorer,
                width: SidePanel.defaultWidth,
              ),
              SidePanelResizeHandle(onDragDelta: deltas.add),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    final handle = find.byType(SidePanelResizeHandle);
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(deltas, isNotEmpty);
    expect(deltas.reduce((a, b) => a + b), greaterThan(20));
  });

  test('side panel width clamps', () {
    expect(SidePanel.minWidth, lessThan(SidePanel.defaultWidth));
    expect(SidePanel.maxWidth, greaterThan(SidePanel.defaultWidth));
    expect(200.0.clamp(SidePanel.minWidth, SidePanel.maxWidth), 200);
    expect(600.0.clamp(SidePanel.minWidth, SidePanel.maxWidth), SidePanel.maxWidth);
    expect(100.0.clamp(SidePanel.minWidth, SidePanel.maxWidth), SidePanel.minWidth);
  });
}
