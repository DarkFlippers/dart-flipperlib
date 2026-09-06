// Desktop DFU host — Dart counterpart to qFlipper's USBDeviceDetector
// (.sources/qflipper/dfu/libusb/usbdevicedetector.cpp): libusb enumerates the
// bus, references the matching device and hands the pointer to the protocol
// layer. Enumeration is fast and safe on the UI isolate; the recovery isolate
// creates its own instance (and libusb context) for the heavy transfers.
//
// libusb hotplug is not wired on every backend we ship, so presence is polled
// on a cheap interval while somebody listens.
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../common/log.dart';
import 'backend.dart';
import 'libusb/libusb.dart';

class LibusbHostBackend implements DfuUsbBackend {
  LibusbHostBackend({this.pollInterval = const Duration(seconds: 1)});

  final Duration pollInterval;

  static const Duration _waitStep = Duration(milliseconds: 100);

  late final StreamController<bool> _presence =
      StreamController<bool>.broadcast(
        onListen: _startPolling,
        onCancel: _stopPolling,
      );
  Timer? _timer;
  bool _last = false;

  @override
  bool get available => Libusb.instance != null;

  @override
  Future<bool> isPresent() async => isPresentSync();

  bool isPresentSync({
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

  @override
  Stream<bool> get presence => _presence.stream;

  @override
  Future<bool> waitPresence(bool present, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (isPresentSync() == present) return true;
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(_waitStep);
    }
  }

  /// Finds the first matching DFU device, adds a reference, and returns it.
  /// The caller owns the reference and must pass it to [release] when done.
  @override
  Future<DfuDeviceRef?> acquire({
    int vendorId = stmDfuVendorId,
    int productId = stmDfuProductId,
  }) async {
    return _withDeviceList<DfuDeviceRef?>((usb, list, count) {
      for (var i = 0; i < count; i++) {
        final dev = (list + i).value;
        if (_matches(dev, vendorId, productId)) {
          usb.refDevice(dev); // survives free_device_list below
          return LibusbDeviceRef(dev.address);
        }
      }
      return null;
    }, orElse: null);
  }

  @override
  Future<void> release(DfuDeviceRef ref) async {
    if (ref is! LibusbDeviceRef) {
      throw ArgumentError('LibusbHostBackend can not release $ref');
    }
    final usb = Libusb.instance;
    if (usb == null || ref.address == 0) return;
    usb.unrefDevice(Pointer<LibusbDevice>.fromAddress(ref.address));
  }

  void _startPolling() {
    _last = isPresentSync();
    if (_last) _presence.add(true);
    _timer = Timer.periodic(pollInterval, (_) {
      final present = isPresentSync();
      if (present == _last) return;
      _last = present;
      _presence.add(present);
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
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
    final ctx = LibusbSession.context;
    if (ctx == null) return orElse;
    final usb = Libusb.instance!;
    final listOut = malloc<Pointer<Pointer<LibusbDevice>>>();
    try {
      final count = usb.getDeviceList(ctx, listOut);
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
