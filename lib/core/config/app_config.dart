class AppConfig {
  // API Configuration
  static const String apiBaseUrl = 'https://veyo.octavions.com';

  // Sync Configuration
  static const Duration syncInterval = Duration(minutes: 5);
  static const bool autoSync = true;

  // App Configuration
  static const String appName = 'Veyo Accounts';
  static const String appVersion = '1.0.0';
}
