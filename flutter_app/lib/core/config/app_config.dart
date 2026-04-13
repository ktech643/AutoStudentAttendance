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
  apiBaseUrl: String.fromEnvironment('FLUTTER_API_BASE_URL', defaultValue: 'http://127.0.0.1:8000'),
  deviceId: String.fromEnvironment('FLUTTER_DEVICE_ID', defaultValue: 'ipad-kiosk-1'),
  simulatedRecognition: bool.fromEnvironment('FLUTTER_SIMULATED_RECOGNITION', defaultValue: true),
  adminEmail: String.fromEnvironment('FLUTTER_ADMIN_EMAIL', defaultValue: 'admin@school.com'),
  adminPassword: String.fromEnvironment('FLUTTER_ADMIN_PASSWORD', defaultValue: 'changeMe123'),
);
