class AppConfig {
  /// Base URL of the Cloudflare Worker, without a trailing slash.
  /// Set at build time:
  ///   flutter run --dart-define=API_BASE_URL=https://oja-pos-api.<you>.workers.dev
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8787',
  );

  static const String appName = 'Oja POS';
}
