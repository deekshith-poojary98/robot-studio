import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/environment_info.dart';
import 'package:robot_studio/core/theme/app_theme.dart';
import 'package:robot_studio/presentation/environment/create_environment_dialog.dart';
import 'package:robot_studio/presentation/environment/python_install_guidance.dart';
import 'package:robot_studio/presentation/widgets/environment_prompt_toast.dart';
import 'package:robot_studio/presentation/widgets/error_dialog.dart';

void main() {
  test('missing-python copy points at install steps', () {
    expect(PythonInstallGuidance.summary, contains('No Python'));
    expect(PythonInstallGuidance.toastTitle, 'Python is not installed');
    expect(
      PythonInstallGuidance.shortRecovery.toLowerCase(),
      contains('install'),
    );
    expect(
      PythonInstallGuidance.matchesError(
        Exception('No Python interpreter found on this machine.'),
      ),
      isTrue,
    );
    expect(
      friendlyErrorRecovery('No Python interpreter found on this machine.'),
      PythonInstallGuidance.shortRecovery,
    );
  });

  test('missing pip when installing RF maps to apt recovery', () {
    final copy = resolveFriendlyError(
      'Failed to install Robot Framework: /usr/bin/python3.14: No module named pip',
    );
    expect(
      copy.summary,
      'Could not install Robot Framework into the new environment.',
    );
    expect(copy.recovery.toLowerCase(), contains('pip'));
  });

  test('PEP 668 system pip maps to venv recovery', () {
    final copy = resolveFriendlyError(
      'Failed to install Robot Framework: error: externally-managed-environment',
    );
    expect(copy.recovery.toLowerCase(), contains('venv'));
  });

  test('missing Robot Framework maps to install recovery', () {
    final copy = resolveFriendlyError(
      'Robot Framework is not installed in the active environment.',
    );
    expect(copy.summary.toLowerCase(), contains('robot framework'));
    expect(copy.recovery.toLowerCase(), contains('install'));
  });

  testWidgets(
    'create env dialog warns when discovery returns no interpreters',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );

      final future = showCreateEnvironmentDialog(
        tester.element(find.byType(SizedBox)),
        loadInterpreters: () async => const <PythonInterpreterInfo>[],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-env.no-python')), findsOneWidget);
      expect(find.text(PythonInstallGuidance.summary), findsWidgets);
      expect(
        find.byKey(const Key('create-env.refresh-interpreters')),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await future, isNull);
    },
  );

  testWidgets('create env dialog uses compact aligned controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    showCreateEnvironmentDialog(
      tester.element(find.byType(SizedBox)),
      loadInterpreters: () async => const [
        PythonInterpreterInfo(
          path: '/usr/bin/python3',
          version: '3.13.0',
          displayName: 'Python 3.13.0 — /usr/bin/python3',
        ),
      ],
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Create Environment'));
    expect(title.style?.fontSize, 18);

    final interpreterField = find.widgetWithText(
      TextField,
      'Python interpreter',
    );
    final browseButton = find.widgetWithText(OutlinedButton, 'Browse…');
    expect(
      tester.getTopLeft(browseButton).dy,
      closeTo(tester.getTopLeft(interpreterField).dy, 1),
    );
    expect(tester.getSize(browseButton).height, 36);

    final checkbox = find.byType(Checkbox);
    final installLabel = find.text('Install Robot Framework');
    expect(
      tester.getTopRight(checkbox).dx,
      lessThan(tester.getTopLeft(installLabel).dx),
    );
    expect(
      tester.getTopLeft(installLabel).dx - tester.getTopRight(checkbox).dx,
      lessThanOrEqualTo(10),
    );
  });

  testWidgets('no-python toast leads with install guidance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            EnvironmentPromptToast(
              title: PythonInstallGuidance.toastTitle,
              message: PythonInstallGuidance.toastMessage,
              actions: const [
                EnvironmentPromptAction(
                  label: 'How to Install',
                  primary: true,
                  onPressed: _noop,
                ),
                EnvironmentPromptAction(
                  label: 'Select Existing…',
                  onPressed: _noop,
                ),
              ],
              onDismiss: _noop,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Python is not installed'), findsOneWidget);
    expect(find.text('How to Install'), findsOneWidget);
    expect(find.textContaining('needs Python 3'), findsOneWidget);
  });
}

void _noop() {}
