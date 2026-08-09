import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/presentation/execution/live_progress_markers.dart';

void main() {
  test('parses marker-only line and drops console text', () {
    final parsed = parseProgressMarker('###RS###|now|Login|Hello|BuiltIn.Log');
    expect(parsed, isNotNull);
    expect(parsed!.suite, 'Login');
    expect(parsed.test, 'Hello');
    expect(parsed.keyword, 'BuiltIn.Log');
    expect(parsed.consoleLine, isNull);
  });

  test('parses marker glued onto Robot padded console row', () {
    final parsed = parseProgressMarker(
      'Login with valid creds :: docs…          ###RS###|now|Login|Login with valid creds|',
    );
    expect(parsed, isNotNull);
    expect(parsed!.suite, 'Login');
    expect(parsed.test, 'Login with valid creds');
    expect(parsed.keyword, '');
    expect(parsed.consoleLine, 'Login with valid creds :: docs…');
  });

  test('returns null when no marker present', () {
    expect(parseProgressMarker('[ WARN ] Browser launched'), isNull);
  });
}
