/// Where Robot Studio asks for the latest release.
///
/// Override at build/run time, e.g. a local update server:
/// `flutter run --dart-define=ROBOT_STUDIO_UPDATE_URL=http://127.0.0.1:8090`
const String kUpdateServiceBaseUrl = String.fromEnvironment(
  'ROBOT_STUDIO_UPDATE_URL',
  defaultValue: 'https://robot-studio-updates.onrender.com',
);

bool get isUpdateCheckConfigured => kUpdateServiceBaseUrl.trim().isNotEmpty;
