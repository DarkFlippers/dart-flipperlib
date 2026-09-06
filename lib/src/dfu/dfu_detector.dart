// Reports whether a Flipper is sitting in the STM32 DFU bootloader. The
// platform host does the watching (libusb enumeration on desktop, UsbManager
// broadcasts on Android); this only tracks the last known state for the UI.
import 'dart:async';
import 'dart:io';

import '../common/log.dart';
import 'android_backend.dart';
import 'backend.dart';
import 'libusb_host_backend.dart';

export 'backend.dart' show stmDfuVendorId, stmDfuProductId;

/// The DFU host for the isolate that owns the UI. One per isolate: on Android
/// it holds the platform channels, on desktop the libusb context.
abstract final class DfuUsb {
  static DfuUsbBackend? _host;

  static DfuUsbBackend get host =>
      _host ??= Platform.isAndroid ? AndroidDfuBackend() : LibusbHostBackend();
}

/// Emits presence transitions (true = a Flipper is in DFU). No-op stream when
/// the platform has no DFU host.
class DfuDetector {
  DfuDetector({DfuUsbBackend? backend}) : _backend = backend ?? DfuUsb.host;

  final DfuUsbBackend _backend;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<bool>? _sub;
  bool _last = false;
  bool _started = false;

  Stream<bool> get presence => _controller.stream;
  bool get isPresent => _last;
  bool get available => _backend.available;

  void start() {
    if (_started || !available) return;
    _started = true;
    _sub = _backend.presence.listen(_update);
    unawaited(
      _backend.isPresent().then((present) {
        if (_started) _update(present);
      }),
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  void _update(bool present) {
    if (present == _last) return;
    _last = present;
    Log.info('[DFU] bootloader ${present ? 'detected' : 'gone'}');
    if (!_controller.isClosed) _controller.add(present);
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }
}
