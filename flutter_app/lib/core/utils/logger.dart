import 'dart:convert';

void logStructured(
  String eventName, {
  Map<String, dynamic>? data,
}) {
  final payload = {
    'event': eventName,
    'ts': DateTime.now().toUtc().toIso8601String(),
    'data': data ?? const <String, dynamic>{},
  };
  // ignore: avoid_print
  print(jsonEncode(payload));
}
