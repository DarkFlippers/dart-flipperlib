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

  static bool get warnOn =>
      sink != null && level.index <= FlipperLogLevel.warning.index;

  /// Returns whether the line went anywhere. [warnOnce] is the caller that
  /// needs to know; everything else can ignore it, as Dart does by default.
  static bool warn(String message) {
    if (!warnOn) return false;
    sink!(FlipperLogLevel.warning, message);
    return true;
  }

  /// A warning said once per isolate, for a fact about the machine rather than
  /// about the call.
  ///
  /// The mechanism lives here rather than at the call site because five call
  /// sites in `transport/ble/linux.dart` wrote it by hand and every one of
  /// them had the same bug: each set its latch after *calling* [warn], and
  /// [warn] says nothing while [sink] is null - which it is until the app
  /// installs one, inside `_initCore` - or while [level] is above `warning`,
  /// which `QLOG_LEVEL=error` does. So each of those notices could be latched
  /// away for the isolate having been said nowhere, under a comment asserting
  /// that writing the assignment second prevented exactly that.
  ///
  /// [topic] is what "once" counts. Two topics never suppress each other,
  /// which matters where two conditions can hold at once - a masked /sys fails
  /// *open* in `linux.dart`, so a confined host reaches the next read too and
  /// both of its lines are true.
  ///
  /// [cause] separates variants within one [topic], for a condition whose
  /// explanation is the useful part: latched on the first cause alone, a
  /// transient one suppresses the diagnosis that follows it. [causes] caps how
  /// many distinct ones are worth saying, because a topic keyed on an error's
  /// text is otherwise unbounded - and these are `warn`, which the app keeps
  /// in release and forwards to Sentry, where volume is what discards real
  /// errors.
  static void warnOnce(
    String topic,
    String message, {
    String cause = '',
    int causes = 1,
  }) {
    final said = _saidOnce.putIfAbsent(topic, () => <String>{});
    if (said.length >= causes || said.contains(cause)) return;
    // Recorded only when it was said. That is the whole point; see above.
    if (warn(message)) said.add(cause);
  }

  static final Map<String, Set<String>> _saidOnce = {};

  /// Lets a test start from a known state; nothing resets a static by itself.
  static void debugResetNotices() => _saidOnce.clear();

  static void error(String message) {
    final s = sink;
    if (s == null) return;
    s(FlipperLogLevel.error, message);
  }
}
