/// Where Robot Studio asks for the latest release.
///
/// Override at build/run time:
/// `flutter run --dart-define=ROBOT_STUDIO_UPDATE_URL=https://updates.example.com`
const String kUpdateServiceBaseUrl = String.fromEnvironment(
  'ROBOT_STUDIO_UPDATE_URL',
  defaultValue: 'http://127.0.0.1:8090',
);

bool get isUpdateCheckConfigured => kUpdateServiceBaseUrl.trim().isNotEmpty;
