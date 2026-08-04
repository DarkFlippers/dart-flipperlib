import 'serial/ports_macos.dart';
import '../../model/device.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'link.dart';
import 'platform.dart';

class MacosUsbPlatform extends SerialUsbPlatformBase {
  const MacosUsbPlatform();

  @override
  Future<List<FlipperDevice>> loadDevices() async {
    return comportsDevices(macosComports);
  }

  @override
  Future<Transport> openTransport(UsbDiscoveredDevice device) {
    if (device is! DesktopUsbDiscoveredDevice) {
      throw UnsupportedError('macOS USB transport requires serial device');
    }
    return MacosUsbTransport.create(device);
  }
}

class MacosUsbTransport extends SerialUsbTransportBase {
  MacosUsbTransport._(
    super.isolate,
    super.eventPort,
    super.events,
    super.commandPort,
  );

  static Future<MacosUsbTransport> create(DesktopUsbDiscoveredDevice device) {
    return SerialUsbTransportBase.createFor(device, MacosUsbTransport._);
  }
}
