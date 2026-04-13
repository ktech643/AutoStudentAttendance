class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.deviceId,
    required this.simulatedRecognition,
    required this.adminEmail,
    required this.adminPassword,
  });

  final String apiBaseUrl;
  final String deviceId;
  final bool simulatedRecognition;
  final String adminEmail;
  final String adminPassword;
}

const defaultAppConfig = AppConfig(
  // Docker container attendx-api is exposed on host port 8008 (0.0.0.0:8008->8000).
  // iPhone reaches it via the Mac's LAN IP.
  apiBaseUrl: String.fromEnvironment('FLUTTER_API_BASE_URL', defaultValue: 'http://192.168.2.146:8008'),
  deviceId: String.fromEnvironment('FLUTTER_DEVICE_ID', defaultValue: 'ipad-kiosk-1'),
  simulatedRecognition: bool.fromEnvironment('FLUTTER_SIMULATED_RECOGNITION', defaultValue: false),
  adminEmail: String.fromEnvironment('FLUTTER_ADMIN_EMAIL', defaultValue: 'admin@school.com'),
  adminPassword: String.fromEnvironment('FLUTTER_ADMIN_PASSWORD', defaultValue: 'changeMe123'),
);
