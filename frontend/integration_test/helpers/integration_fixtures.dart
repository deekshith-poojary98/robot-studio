/// Embedded fixtures for integration tests.
///
/// macOS app sandbox cannot read files from the repository checkout, so test
/// assets are compiled into the test bundle.
class IntegrationFixtures {
  IntegrationFixtures._();

  static const sampleRobot = '''*** Settings ***
Documentation    Minimal suite for integration tests

*** Test Cases ***
Hello Integration
    Log    integration test
''';

  static const testPluginJson = '''
{
  "id": "integration-test-plugin",
  "name": "Integration Test Plugin",
  "version": "0.0.1",
  "author": "Robot Studio Tests",
  "description": "Fake plugin used by integration tests",
  "entry": "plugin.py",
  "capabilities": ["toolbar-action"]
}
''';

  static const testPluginPy = '''"""Minimal plugin used by Flutter integration tests."""


class Plugin:
    async def initialize(self, context) -> None:
        return None

    async def activate(self, context) -> None:
        return None

    async def deactivate(self, context) -> None:
        return None

    async def dispose(self, context) -> None:
        return None
''';
}
