import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as pretty_logging;
import 'package:logging/logging.dart' as logging;
import 'package:universal_ble/universal_ble.dart';

class LogService {
  // Compile-time logging switch. Hot paths (per-chunk RX, per-frame routing,
  // per-write BLE) must guard with `if (LogService.enabled)` so release builds
  // skip building the interpolated message strings entirely.
  static const bool enabled = kDebugMode;

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!kDebugMode || _initialized) return;
    _initialized = true;

    logging.Logger.root.level = logging.Level.ALL;
    logging.Logger.root.onRecord.listen((record) {
      final source = record.loggerName.isEmpty ? 'library' : record.loggerName;
      _write('[${record.level.name}][$source] ${record.message}');
      _writeError(record.error, record.stackTrace);
    });

    pretty_logging.Logger.defaultOutput = _LogServiceOutput.new;
    await UniversalBle.setLogLevel(BleLogLevel.info);
  }

  static void log(String msg) {
    if (!kDebugMode) return;

    _write(msg);
  }

  static void _writeError(Object? error, StackTrace? stackTrace) {
    if (error != null) _write('error: $error');
    if (stackTrace != null) _write(stackTrace.toString());
  }

  static void _write(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    for (final line in msg.split('\n')) {
      debugPrint('[$ts] $line');
    }
  }
}

class _LogServiceOutput extends pretty_logging.LogOutput {
  @override
  void output(pretty_logging.OutputEvent event) {
    final origin = event.origin;
    LogService._write(
      '[${origin.level.name.toUpperCase()}][library] '
      '${origin.message}',
    );
    LogService._writeError(origin.error, origin.stackTrace);
  }
}
