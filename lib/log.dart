library;

enum FlipperLogLevel { trace, debug, info, warning, error }

typedef FlipperLogSink = void Function(FlipperLogLevel level, String message);

abstract final class Log {
  static const bool debugBuild =
      !bool.fromEnvironment('dart.vm.product') &&
      !bool.fromEnvironment('dart.vm.profile');

  static FlipperLogLevel level = FlipperLogLevel.info;
  static FlipperLogSink? sink;

  static bool get traceOn =>
      debugBuild && sink != null && level.index <= FlipperLogLevel.trace.index;

  static bool get debugOn =>
      debugBuild && sink != null && level.index <= FlipperLogLevel.debug.index;

  static void trace(String message) {
    if (traceOn) sink!(FlipperLogLevel.trace, message);
  }

  static void debug(String message) {
    if (debugOn) sink!(FlipperLogLevel.debug, message);
  }

  static void info(String message) {
    final s = sink;
    if (s == null || level.index > FlipperLogLevel.info.index) return;
    s(FlipperLogLevel.info, message);
  }

  static void warn(String message) {
    final s = sink;
    if (s == null || level.index > FlipperLogLevel.warning.index) return;
    s(FlipperLogLevel.warning, message);
  }

  static void error(String message) {
    final s = sink;
    if (s == null) return;
    s(FlipperLogLevel.error, message);
  }
}
