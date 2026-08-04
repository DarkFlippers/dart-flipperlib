import 'serial/ports_linux.dart';
import '../../model/device.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'link.dart';
import 'platform.dart';

class LinuxUsbPlatform extends SerialUsbPlatformBase {
  const LinuxUsbPlatform();

  @override
  Future<List<FlipperDevice>> loadDevices() async {
    return comportsDevices(linuxComports);
  }

  @override
  Future<Transport> openTransport(UsbDiscoveredDevice device) {
    if (device is! DesktopUsbDiscoveredDevice) {
      throw UnsupportedError('Linux USB transport requires serial device');
    }
    return LinuxUsbTransport.create(device);
  }
}

class LinuxUsbTransport extends SerialUsbTransportBase {
  LinuxUsbTransport._(
    super.isolate,
    super.eventPort,
    super.events,
    super.commandPort,
  );

  static Future<LinuxUsbTransport> create(DesktopUsbDiscoveredDevice device) {
    return SerialUsbTransportBase.createFor(device, LinuxUsbTransport._);
  }
}
