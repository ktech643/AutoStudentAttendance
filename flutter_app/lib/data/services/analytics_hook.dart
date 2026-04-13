abstract class AnalyticsHook {
  void track(String eventName, {Map<String, dynamic>? properties});
}

class ConsoleAnalyticsHook implements AnalyticsHook {
  @override
  void track(String eventName, {Map<String, dynamic>? properties}) {
    // Placeholder hook for integrating Firebase/Segment or school analytics pipeline.
    final payload = {
      'event': eventName,
      'properties': properties ?? const <String, dynamic>{},
      'ts': DateTime.now().toUtc().toIso8601String(),
    };
    // ignore: avoid_print
    print(payload);
  }
}
