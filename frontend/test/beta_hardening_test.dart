import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/transport_gateway.dart';
import 'package:robot_studio/presentation/shell/controllers/editor_shell_controller.dart';

void main() {
  test('GatewayException exposes large-run confirmation fields', () {
    final error = GatewayException(
      'Confirm large run',
      code: 'large_run_confirmation_required',
      count: 1582,
      threshold: 100,
    );
    expect(error.isLargeRunConfirmation, isTrue);
    expect(error.count, 1582);
    expect(error.threshold, 100);
  });

  test('IndexedSymbolInfo parses multiple definitions', () {
    final symbol = IndexedSymbolInfo.fromJson({
      'id': 'k1',
      'name': 'Shared Keyword',
      'kind': 'keyword',
      'file_path': '/tmp/a.robot',
      'line': 2,
      'definitions': [
        {
          'id': 'k1',
          'name': 'Shared Keyword',
          'kind': 'keyword',
          'file_path': '/tmp/a.robot',
          'line': 2,
        },
        {
          'id': 'k2',
          'name': 'Shared Keyword',
          'kind': 'keyword',
          'file_path': '/tmp/b.robot',
          'line': 5,
        },
      ],
    });
    expect(symbol.definitions, hasLength(2));
    expect(symbol.definitions[1].filePath, '/tmp/b.robot');
  });

  test('DiagnosticInfo keeps analysis source and inspection id', () {
    final diagnostic = DiagnosticInfo.fromJson({
      'severity': 'warning',
      'file_path': '/tmp/login.robot',
      'line': 2,
      'column': 1,
      'message': "Unresolved import 'missing.resource'",
      'source': 'analysis',
      'code': 'missing_import',
      'inspection_id': 'missing_import',
    });
    expect(diagnostic.source, 'analysis');
    expect(diagnostic.code, 'missing_import');
    expect(diagnostic.inspectionId, 'missing_import');
    expect(diagnostic.sourceLabel, contains('analysis'));
  });

  test('extractRobotTokenAt prefers Robot cells', () {
    const content = '*** Test Cases ***\nLogin\n    Shared Keyword    arg\n';
    final token = EditorShellController.extractRobotTokenAt(content, 3, 8);
    expect(token, 'Shared Keyword');
  });
}
