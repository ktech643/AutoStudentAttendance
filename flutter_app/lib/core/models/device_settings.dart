import '../config/attendance_thresholds.dart';

class DeviceSettings {
  const DeviceSettings({
    required this.deviceId,
    required this.thresholds,
  });

  final String deviceId;
  final AttendanceThresholds thresholds;

  factory DeviceSettings.fromJson(Map<String, dynamic> json) {
    return DeviceSettings(
      deviceId: json['device_id'] as String,
      thresholds: AttendanceThresholds.fromMap(json),
    );
  }

  Map<String, dynamic> toJson() => thresholds.toMap(deviceId);
}
