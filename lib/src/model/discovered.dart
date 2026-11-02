import 'package:universal_ble/universal_ble.dart' as uble;
import 'package:usb_serial/usb_serial.dart';

import 'device_id.dart';

enum DeviceTransport { ble, usb }

/// A device found during discovery. Carries just enough platform identity for
/// the client to open the matching transport; connection logic lives in the
/// transport implementations (ble/*.dart, usb/*.dart).
abstract class DiscoveredDevice {
  String get id;
  String get name;
  DeviceTransport get transport;
}

// USB discovered (abstract)

abstract class UsbDiscoveredDevice implements DiscoveredDevice {
  @override
  DeviceTransport get transport => DeviceTransport.usb;
}

// BLE discovered

class BleDiscoveredDevice implements DiscoveredDevice {
  /// Canonicalises the plugin's id here, so that no part of this library can
  /// hold one in a spelling the plugin will not emit.
  ///
  /// It is applied in `FlipperClient.connectBleAddress` as well, because that
  /// is where an id from a *caller's* store arrives and the cache is keyed
  /// before any wrapper exists. This is the structural half: a scan result,
  /// `loadKnownDevices`, and a consumer calling the exported
  /// `blePlatform.openTransport` all pass through here, and
  /// [UniversalBleTransportBase] keys its callback dispatch off [id]. Without
  /// it the invariant held by audit - every site that compared an id happened
  /// to have a canonical one - and #444 is what that costs when one does not:
  /// a link that connects and then silently carries nothing.
  ///
  /// [device] keeps the plugin's own spelling, which is what the plugin is
  /// handed back. It accepts either case; nothing in this library compares it.
  BleDiscoveredDevice(this.device) : id = canonicalBleDeviceId(device.deviceId);

  final uble.BleDevice device;

  @override
  final String id;

  @override
  String get name =>
      (device.name?.isNotEmpty == true) ? device.name! : device.deviceId;

  @override
  DeviceTransport get transport => DeviceTransport.ble;

  int get rssi => device.rssi?.toInt() ?? 0;
}

// Android USB discovered

class AndroidUsbDiscoveredDevice extends UsbDiscoveredDevice {
  final UsbDevice usbDevice;
  AndroidUsbDiscoveredDevice(this.usbDevice);

  @override
  String get id => '${usbDevice.vid}:${usbDevice.pid}';

  @override
  String get name {
    final p = usbDevice.productName;
    if (p != null && p.isNotEmpty) return p;
    return 'USB VID:0x${usbDevice.vid?.toRadixString(16) ?? '?'} '
        'PID:0x${usbDevice.pid?.toRadixString(16) ?? '?'}';
  }
}

// Desktop USB discovered (Windows / macOS / Linux)

class DesktopUsbDiscoveredDevice extends UsbDiscoveredDevice {
  final String portName;
  final String description;
  final String hwid;
  final int? vendorId;
  final int? productId;
  final String? serialNumber;

  DesktopUsbDiscoveredDevice(
    this.portName,
    this.description, {
    this.hwid = 'n/a',
    this.vendorId,
    this.productId,
    this.serialNumber,
  });

  @override
  String get id => portName;

  @override
  String get name => description.isNotEmpty ? description : portName;
}
