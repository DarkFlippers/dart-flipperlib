// Raw-USB device wrapper over libusb — Dart port of qFlipper's USBDevice
// (.sources/qflipper/dfu/libusb/usbdevice.cpp). Synchronous on purpose: the
// DfuSe layer above polls device status with blocking sleeps exactly like
// qFlipper's worker thread, so every recovery flow that uses this backend must
// run inside a dedicated isolate (never the UI isolate).
//
// The device arrives as a [DfuDeviceRef]: a referenced libusb_device* where
// libusb enumerates the bus, or an already open file descriptor (Android) that
// libusb_wrap_sys_device turns into a handle. From the handle on both paths are
// identical.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../common/log.dart';
import 'backend.dart';
import 'libusb/libusb.dart';

class UsbDeviceBackend {
  UsbDeviceBackend(this.ref) : _usb = Libusb.instance!;

  /// The host-reserved device this wrapper opens.
  final DfuDeviceRef ref;

  final Libusb _usb;
  Pointer<LibusbDevice> _device = nullptr;
  Pointer<LibusbDeviceHandle> _handle = nullptr;

  /// libusb error of the last failed [open], for the caller to classify
  /// (driver missing vs. access denied); [libusbSuccess] otherwise.
  int lastOpenError = libusbSuccess;

  /// Control-transfer timeout, mirrors qFlipper's `m_timeout`.
  int timeoutMs = 5000;

  // qFlipper retries every USB op 25×50ms — matters during re-enumeration when
  // the OS has not finished attaching the bootloader interface yet.
  static const int _retryCount = 25;
  static const int _retryIntervalMs = 50;

  bool get isOpen => _handle != nullptr;

  bool open() {
    if (_handle != nullptr) return true;
    final out = malloc<Pointer<LibusbDeviceHandle>>();
    try {
      final int err;
      switch (ref) {
        case LibusbDeviceRef(:final address):
          err = _usb.open(Pointer<LibusbDevice>.fromAddress(address), out);
        case UsbFdDeviceRef(:final fd):
          final ctx = LibusbSession.context;
          if (ctx == null) {
            lastOpenError = libusbErrorNotSupported;
            Log.error('[DFU] libusb context unavailable');
            return false;
          }
          err = _usb.wrapSysDevice(ctx, fd, out);
      }
      if (err != libusbSuccess) {
        lastOpenError = err;
        Log.error('[DFU] libusb open failed: ${_usb.errorString(err)}');
        return false;
      }
      lastOpenError = libusbSuccess;
      _handle = out.value;
      _device = _usb.getDevice(_handle);
      // Best-effort: lets us claim an interface the kernel may have bound.
      try {
        _usb.setAutoDetachKernelDriver(_handle, 1);
      } catch (_) {}
      return true;
    } finally {
      malloc.free(out);
    }
  }

  void close() {
    if (_handle == nullptr) return;
    _usb.close(_handle);
    _handle = nullptr;
    _device = nullptr;
  }

  bool claimInterface(int interfaceNum) => _retry(
    () => _usb.claimInterface(_handle, interfaceNum),
    'claimInterface',
  );

  bool releaseInterface(int interfaceNum) {
    final err = _usb.releaseInterface(_handle, interfaceNum);
    if (err != libusbSuccess) {
      Log.error('[DFU] releaseInterface failed: ${_usb.errorString(err)}');
    }
    return err == libusbSuccess;
  }

  bool setInterfaceAltSetting(int interfaceNum, int alt) => _retry(
    () => _usb.setInterfaceAltSetting(_handle, interfaceNum, alt),
    'setInterfaceAltSetting',
  );

  /// OUT control transfer. Returns true iff the full [data] was transferred.
  bool controlTransferOut(
    int requestType,
    int request,
    int value,
    int index,
    Uint8List data,
  ) {
    final len = data.length;
    final buf = len == 0 ? nullptr : malloc<Uint8>(len);
    try {
      if (len > 0) buf.asTypedList(len).setAll(0, data);
      var res = -1;
      for (var retry = _retryCount; retry > 0; retry--) {
        res = _usb.controlTransfer(
          _handle,
          requestType,
          request,
          value,
          index,
          buf,
          len,
          timeoutMs,
        );
        if (res >= 0) break;
        sleep(const Duration(milliseconds: _retryIntervalMs));
      }
      if (res < 0) {
        Log.error('[DFU] control OUT failed: ${_usb.errorString(res)}');
      }
      return res == len;
    } finally {
      if (len > 0) malloc.free(buf);
    }
  }

  /// IN control transfer. Returns the bytes read (length may be < [length] at
  /// end of memory), or an empty list on error.
  Uint8List controlTransferIn(
    int requestType,
    int request,
    int value,
    int index,
    int length,
  ) {
    final buf = malloc<Uint8>(length);
    try {
      var res = -1;
      for (var retry = _retryCount; retry > 0; retry--) {
        res = _usb.controlTransfer(
          _handle,
          requestType,
          request,
          value,
          index,
          buf,
          length,
          timeoutMs,
        );
        if (res >= 0) break;
        sleep(const Duration(milliseconds: _retryIntervalMs));
      }
      if (res < 0) {
        Log.error('[DFU] control IN failed: ${_usb.errorString(res)}');
        return Uint8List(0);
      }
      return Uint8List.fromList(buf.asTypedList(res));
    } finally {
      malloc.free(buf);
    }
  }

  /// Returns the device's class-specific extra descriptor of [type] and
  /// [length] under [interfaceNum] (used to read the DFU functional descriptor
  /// → max transfer size). Empty when not present.
  Uint8List extraInterfaceDescriptor(int interfaceNum, int type, int length) {
    final cfgOut = malloc<Pointer<LibusbConfigDescriptor>>();
    try {
      if (_usb.getConfigDescriptor(_device, 0, cfgOut) != libusbSuccess) {
        Log.error('[DFU] getConfigDescriptor failed');
        return Uint8List(0);
      }
      final cfg = cfgOut.value;
      try {
        final intf = (cfg.ref.interface1 + interfaceNum).ref;
        for (var i = 0; i < intf.numAltsetting; i++) {
          final alt = (intf.altsetting + i).ref;
          if (alt.extraLength == length &&
              alt.extra != nullptr &&
              alt.extra[1] == type) {
            return Uint8List.fromList(alt.extra.asTypedList(alt.extraLength));
          }
        }
        return Uint8List(0);
      } finally {
        _usb.freeConfigDescriptor(cfg);
      }
    } finally {
      malloc.free(cfgOut);
    }
  }

  /// ASCII string descriptor for alt setting [alt]'s iInterface (the DfuSe
  /// memory-layout string, e.g. `@Internal Flash /0x08000000/...`).
  String stringInterfaceDescriptor(int alt) {
    final cfgOut = malloc<Pointer<LibusbConfigDescriptor>>();
    final buf = malloc<Uint8>(255);
    try {
      if (_usb.getConfigDescriptor(_device, 0, cfgOut) != libusbSuccess) {
        return '';
      }
      final cfg = cfgOut.value;
      try {
        final intf = cfg.ref.interface1.ref; // first interface
        final descIndex = (intf.altsetting + alt).ref.iInterface;
        final res = _usb.getStringDescriptorAscii(_handle, descIndex, buf, 254);
        if (res < 0) {
          Log.error('[DFU] string descriptor failed: ${_usb.errorString(res)}');
          return '';
        }
        return String.fromCharCodes(buf.asTypedList(res));
      } finally {
        _usb.freeConfigDescriptor(cfg);
      }
    } finally {
      malloc.free(cfgOut);
      malloc.free(buf);
    }
  }

  bool _retry(int Function() op, String what) {
    var err = -1;
    for (var retry = _retryCount; retry > 0; retry--) {
      err = op();
      if (err == libusbSuccess) break;
      sleep(const Duration(milliseconds: _retryIntervalMs));
    }
    if (err != libusbSuccess) {
      Log.error('[DFU] $what failed: ${_usb.errorString(err)}');
    }
    return err == libusbSuccess;
  }
}
