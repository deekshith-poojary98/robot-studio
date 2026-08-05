import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/core/settings/app_settings_controller.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/preferences/editor_font_families.dart';
import 'package:robot_studio/presentation/preferences/preferences_page.dart';

class _SettingsGateway implements TransportGateway {
  AppSettings stored = const AppSettings();
  int updateCalls = 0;
  int resetCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<AppSettings> getSettings() async => stored;

  /// Mirrors the backend: a patch merges into stored settings, it does not
  /// replace them.
  @override
  Future<AppSettings> updateSettings(Map<String, dynamic> payload) async {
    updateCalls++;
    stored = AppSettings.fromJson(_deepMerge(stored.toJson(), payload));
    return stored;
  }

  @override
  Future<AppSettings> resetSettings() async {
    resetCalls++;
    stored = const AppSettings();
    return stored;
  }
}

Map<String, dynamic> _deepMerge(
  Map<String, dynamic> into,
  Map<String, dynamic> patch,
) {
  final result = Map<String, dynamic>.from(into);
  for (final entry in patch.entries) {
    final existing = result[entry.key];
    final incoming = entry.value;
    result[entry.key] =
        (existing is Map<String, dynamic> && incoming is Map<String, dynamic>)
        ? _deepMerge(existing, incoming)
        : incoming;
  }
  return result;
}

/// Reads the switch that belongs to a labelled settings row.
bool _switchValue(WidgetTester tester, String label) {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  return tester
      .widget<Switch>(find.descendant(of: row, matching: find.byType(Switch)))
      .value;
}

Future<void> _tapSwitch(WidgetTester tester, String label) async {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  AppSettingsController controller, {
  VoidCallback? onClose,
}) async {
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

  testWidgets('Discard rolls the draft back without calling the backend', (
    tester,
  ) async {
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

  testWidgets('adopts a setting toggled elsewhere while the page is open', (
    tester,
  ) async {
    final gateway = _SettingsGateway();
    final controller = AppSettingsController(gateway: gateway);
    await controller.load();
    await _pump(tester, controller);

    expect(_switchValue(tester, 'Word Wrap'), isTrue);

    // Edit ▸ Word Wrap patches the controller behind the page's back.
    await controller.patch({
      'editor': {'word_wrap': false},
    });
    await tester.pumpAndSettle();

    expect(_switchValue(tester, 'Word Wrap'), isFalse);
    // Nothing local changed, so there is nothing to save back.
    expect(find.text('Unsaved changes'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('an external change keeps unsaved edits to other fields', (
    tester,
  ) async {
    final gateway = _SettingsGateway();
    final controller = AppSettingsController(gateway: gateway);
    await controller.load();
    await _pump(tester, controller);

    await _tapSwitch(tester, 'Auto Save');

    // Change font family via the curated dropdown (was a free-text field).
    final fontRow = find.ancestor(
      of: find.text('Font Family'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: fontRow,
        matching: find.byType(DropdownButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('JetBrains Mono').last);
    await tester.pumpAndSettle();

    await controller.patch({
      'editor': {'word_wrap': false},
    });
    await tester.pumpAndSettle();

    expect(_switchValue(tester, 'Word Wrap'), isFalse, reason: 'takes theirs');
    expect(_switchValue(tester, 'Auto Save'), isTrue, reason: 'keeps mine');
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.descendant(
              of: fontRow,
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .value,
      'JetBrains Mono',
    );
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('font family offers the curated IDE list', (tester) async {
    final gateway = _SettingsGateway();
    final controller = AppSettingsController(gateway: gateway);
    await _pump(tester, controller);

    final fontRow = find.ancestor(
      of: find.text('Font Family'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(
        of: fontRow,
        matching: find.byType(DropdownButton<String>),
      ),
    );
    await tester.pumpAndSettle();

    for (final family in kEditorFontFamilies) {
      expect(find.text(family).hitTestable(), findsWidgets);
    }
  });

  testWidgets('saving after an external change writes both values', (
    tester,
  ) async {
    final gateway = _SettingsGateway();
    final controller = AppSettingsController(gateway: gateway);
    await controller.load();
    await _pump(tester, controller);

    await _tapSwitch(tester, 'Auto Save');
    await controller.patch({
      'editor': {'word_wrap': false},
    });
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(gateway.stored.editor.autoSave, isTrue);
    expect(gateway.stored.editor.wordWrap, isFalse);
    expect(find.text('Settings saved'), findsOneWidget);
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
