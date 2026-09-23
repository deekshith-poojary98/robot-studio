/// Public update middleman (Render). Fixed — not overridden per build.
const String kUpdateServiceBaseUrl =
    'https://robot-studio-updates.onrender.com';

bool get isUpdateCheckConfigured => kUpdateServiceBaseUrl.trim().isNotEmpty;
