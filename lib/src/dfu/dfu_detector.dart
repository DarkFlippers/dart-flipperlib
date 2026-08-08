// Raw-USB DFU presence detector — Dart counterpart to qFlipper's
// USBDeviceDetector (.sources/qflipper/dfu/libusb/usbdevicedetector.cpp).
// libusb hotplug is not available on every backend (notably macOS), so this
// polls the device list on a cheap interval and reports whether a Flipper is
// sitting in the STM32 DFU bootloader. Enumeration is fast and safe on the UI
// isolate; the heavy recovery transfers run elsewhere.
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../common/log.dart';
import 'libusb/libusb.dart';

/// STM32 system bootloader USB identity — what a Flipper enumerates as in DFU.
const int stmDfuVendorId = 0x0483;
const int stmDfuProductId = 0xDF11;

/// Owns the libusb context and shared enumeration. Single instance so the
/// context is created once for both detection and recovery.
class DfuUsb {
  DfuUsb._();
  static final DfuUsb instance = DfuUsb._();

  Pointer<LibusbContext> _ctx = nullptr;
  bool _initFailed = false;

  /// True when a vendored libusb is present on this platform.
  bool get available => Libusb.instance != null;

  bool _ensureInit() {
    if (_ctx != nullptr) return true;
    if (_initFailed) return false;
    final usb = Libusb.instance;
    if (usb == null) {
      _initFailed = true;
      return false;
    }
    final out = malloc<Pointer<LibusbContext>>();
    try {
      final err = usb.init(out);
      if (err != libusbSuccess) {
        Log.error('[DFU] libusb_init failed: ${usb.errorString(err)}');
        _initFailed = true;
        return false;
      }
      _ctx = out.value;
      return true;
    } finally {
      malloc.free(out);
    }
  }

  /// Whether at least one device matching [vendorId]/[productId] is on the bus.
  bool isPresent({
    int vendorId = stmDfuVendorId,
    int productId = stmDfuProductId,
  }) {
    return _withDeviceList((usb, list, count) {
      for (var i = 0; i < count; i++) {
        if (_matches((list + i).value, vendorId, productId)) return true;
      }
      return false;
    }, orElse: false);
  }

  /// Finds the first matching DFU device, adds a reference, and returns its
  /// pointer address. The caller owns the reference and must pass it to
  /// [releaseDevice] when done. Returns null when none is present.
  int? acquireDevice({
    int vendorId = stmDfuVendorId,
    int productId = stmDfuProductId,
  }) {
    return _withDeviceList<int?>((usb, list, count) {
      for (var i = 0; i < count; i++) {
        final dev = (list + i).value;
        if (_matches(dev, vendorId, productId)) {
          usb.refDevice(dev); // survives free_device_list below
          return dev.address;
        }
      }
      return null;
    }, orElse: null);
  }

  /// Drops a reference taken by [acquireDevice].
  void releaseDevice(int address) {
    final usb = Libusb.instance;
    if (usb == null || address == 0) return;
    usb.unrefDevice(Pointer<LibusbDevice>.fromAddress(address));
  }

  bool _matches(Pointer<LibusbDevice> dev, int vendorId, int productId) {
    final usb = Libusb.instance!;
    final desc = malloc<LibusbDeviceDescriptor>();
    try {
      if (usb.getDeviceDescriptor(dev, desc) != libusbSuccess) return false;
      return desc.ref.idVendor == vendorId && desc.ref.idProduct == productId;
    } finally {
      malloc.free(desc);
    }
  }

  T _withDeviceList<T>(
    T Function(Libusb usb, Pointer<Pointer<LibusbDevice>> list, int count)
    body, {
    required T orElse,
  }) {
    if (!_ensureInit()) return orElse;
    final usb = Libusb.instance!;
    final listOut = malloc<Pointer<Pointer<LibusbDevice>>>();
    try {
      final count = usb.getDeviceList(_ctx, listOut);
      if (count < 0) {
        Log.error('[DFU] getDeviceList failed: ${usb.errorString(count)}');
        return orElse;
      }
      final list = listOut.value;
      try {
        return body(usb, list, count);
      } finally {
        usb.freeDeviceList(list, 1); // unref enumerated devices
      }
    } finally {
      malloc.free(listOut);
    }
  }
}

/// Polls for DFU-bootloader presence and emits transitions (true = a Flipper is
/// in DFU). No-op stream when the platform has no libusb.
class DfuDetector {
  DfuDetector({this.interval = const Duration(seconds: 1)});

  final Duration interval;
  final _controller = StreamController<bool>.broadcast();
  Timer? _timer;
  bool _last = false;
  bool _started = false;

  Stream<bool> get presence => _controller.stream;
  bool get isPresent => _last;
  bool get available => DfuUsb.instance.available;

  void start() {
    if (_started || !available) return;
    _started = true;
    _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  void _poll() {
    final present = DfuUsb.instance.isPresent();
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
