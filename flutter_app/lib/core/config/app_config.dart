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
  // Default matches scripts/run_ios_device.sh (Mac LAN IP from lib_mac_ip.sh + Docker :8008).
  // Override at build time: --dart-define=FLUTTER_API_BASE_URL=http://<ip>:8008
  apiBaseUrl: String.fromEnvironment(
    'FLUTTER_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8008',
  ),
  deviceId: String.fromEnvironment('FLUTTER_DEVICE_ID', defaultValue: 'ipad-kiosk-1'),
  simulatedRecognition: bool.fromEnvironment('FLUTTER_SIMULATED_RECOGNITION', defaultValue: false),
  adminEmail: String.fromEnvironment('FLUTTER_ADMIN_EMAIL', defaultValue: 'admin@school.com'),
  adminPassword: String.fromEnvironment('FLUTTER_ADMIN_PASSWORD', defaultValue: 'changeMe123'),
);
