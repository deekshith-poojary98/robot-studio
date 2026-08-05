import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/settings_info.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/core/settings/app_settings_controller.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/preferences/preferences_page.dart';

class _SettingsGateway implements TransportGateway {
  AppSettings stored = const AppSettings();
  int updateCalls = 0;
  int resetCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<AppSettings> getSettings() async => stored;

  @override
  Future<AppSettings> updateSettings(Map<String, dynamic> payload) async {
    updateCalls++;
    stored = AppSettings.fromJson(payload);
    return stored;
  }

  @override
  Future<AppSettings> resetSettings() async {
    resetCalls++;
    stored = const AppSettings();
    return stored;
  }
}

Future<void> _pump(WidgetTester tester, AppSettingsController controller,
    {VoidCallback? onClose}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: PreferencesPage(controller: controller, onClose: onClose),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on Editor and switches categories', (tester) async {
    final controller = AppSettingsController(gateway: _SettingsGateway());
    await _pump(tester, controller);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Auto Save'), findsOneWidget);
    expect(find.text('Stop Confirmation'), findsNothing);

    await tester.tap(find.text('Execution'));
    await tester.pumpAndSettle();

    expect(find.text('Stop Confirmation'), findsOneWidget);
    expect(find.text('Auto Save'), findsNothing);
  });

  testWidgets('Save stays disabled until something changes', (tester) async {
    final gateway = _SettingsGateway();
    final controller = AppSettingsController(gateway: gateway);
    await _pump(tester, controller);

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

    expect(saveButton().onPressed, isNull);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(saveButton().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(gateway.updateCalls, 1);
    expect(gateway.stored.editor.autoSave, isTrue);
    expect(find.text('Settings saved'), findsOneWidget);
    expect(saveButton().onPressed, isNull);
  });

  testWidgets('Discard rolls the draft back without calling the backend',
      (tester) async {
    final gateway = _SettingsGateway();
    final controller = AppSettingsController(gateway: gateway);
    await _pump(tester, controller);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsNothing);
    expect(gateway.updateCalls, 0);
  });

  testWidgets('close button reports back to the shell', (tester) async {
    var closed = false;
    final controller = AppSettingsController(gateway: _SettingsGateway());
    await _pump(tester, controller, onClose: () => closed = true);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });
}
