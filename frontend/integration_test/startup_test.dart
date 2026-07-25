import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/integration_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = IntegrationHarness();

  setUpAll(() async => harness.setUpAll());
  tearDownAll(() async => harness.tearDownAll());

  testWidgets('application startup connects to backend and shows welcome screen',
      (tester) async {
    await harness.launchApp(tester);

    expect(find.text('Robot Studio'), findsOneWidget);
    expect(find.text('CONNECTED'), findsNothing);
    expect(find.text('OFFLINE'), findsNothing);
    expect(find.text('Open Project'), findsOneWidget);
    expect(find.text('Recent Workspaces'), findsOneWidget);
    expect(find.text('Recent Projects'), findsOneWidget);
    expect(find.text('New Workspace'), findsWidgets);

    harness.expectNoFlutterErrors();
  });
}
