import 'package:universal_ble/universal_ble.dart' as uble;
import 'package:usb_serial/usb_serial.dart';

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
  final uble.BleDevice device;
  const BleDiscoveredDevice(this.device);

  @override
  String get id => device.deviceId;

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
