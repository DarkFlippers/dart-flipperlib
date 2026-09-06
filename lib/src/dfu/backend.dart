// Host side of the DFU stack: who finds the STM32 bootloader on the bus and
// hands the protocol layer something libusb can open. The DfuSe / STM32WB55
// layers stay synchronous (a 1:1 port of qFlipper's worker), so this seam is
// the only place that differs per platform:
//   - desktop: libusb enumerates the bus itself (LibusbHostBackend);
//   - Android: UsbManager owns the device, hands over a file descriptor that
//     libusb wraps (AndroidDfuBackend on the main isolate, reached from the
//     recovery isolate through DfuProxyClient).
import 'dart:async';

/// STM32 system bootloader USB identity — what a Flipper enumerates as in DFU.
const int stmDfuVendorId = 0x0483;
const int stmDfuProductId = 0xDF11;

/// Opaque handle to a DFU device the backend has reserved for the caller. Plain
/// data so it can cross isolate boundaries.
sealed class DfuDeviceRef {
  const DfuDeviceRef();
}

/// A referenced `libusb_device*` from the enumerating backend; released with
/// libusb_unref_device.
class LibusbDeviceRef extends DfuDeviceRef {
  const LibusbDeviceRef(this.address);
  final int address;

  @override
  bool operator ==(Object other) =>
      other is LibusbDeviceRef && other.address == address;

  @override
  int get hashCode => address;
}

/// A file descriptor of an open UsbDeviceConnection (Android). libusb wraps it
/// without taking ownership; the host closes it on [DfuUsbBackend.release].
class UsbFdDeviceRef extends DfuDeviceRef {
  const UsbFdDeviceRef(this.fd);
  final int fd;

  @override
  bool operator ==(Object other) => other is UsbFdDeviceRef && other.fd == fd;

  @override
  int get hashCode => fd;
}

/// Why a device could not be reached. Surfaced to the UI so the user gets an
/// actionable message instead of a bare libusb error code.
enum DfuHostFailure {
  /// Windows: no WinUSB-class driver bound to the bootloader, libusb can not
  /// open it (LIBUSB_ERROR_NOT_SUPPORTED).
  driverMissing,

  /// The OS refused access (LIBUSB_ERROR_ACCESS — e.g. another process holds
  /// the device).
  accessDenied,

  /// Android: the user declined the USB permission dialog.
  permissionDenied,

  /// Anything else.
  other,
}

class DfuHostException implements Exception {
  const DfuHostException(this.failure, this.message);
  final DfuHostFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Platform host for DFU devices. All methods are safe to call from the isolate
/// that owns the backend; blocking implementations are wrapped in futures so
/// the recovery runner reads the same on every platform.
abstract class DfuUsbBackend {
  /// Whether this platform can reach the bootloader at all.
  bool get available;

  /// Whether a device matching the STM32 bootloader identity is on the bus.
  Future<bool> isPresent();

  /// Presence transitions (true = bootloader appeared, false = gone). Emits
  /// only changes; consumers query [isPresent] for the initial state.
  Stream<bool> get presence;

  /// Waits until presence equals [present]. Returns false on timeout.
  Future<bool> waitPresence(bool present, Duration timeout);

  /// Reserves the first DFU device on the bus for the caller, or null when
  /// none is present. May throw [DfuHostException] when the device exists but
  /// can not be handed over (permission denied).
  Future<DfuDeviceRef?> acquire();

  /// Returns a device taken with [acquire].
  Future<void> release(DfuDeviceRef ref);
}
