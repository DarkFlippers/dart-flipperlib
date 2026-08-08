import 'serial/ports_windows.dart';
import '../../model/device.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'link.dart';
import 'platform.dart';

class WindowsUsbPlatform extends SerialUsbPlatformBase {
  const WindowsUsbPlatform();

  @override
  Future<List<FlipperDevice>> loadDevices() async {
    return comportsDevices(windowsComports);
  }

  @override
  Future<Transport> openTransport(UsbDiscoveredDevice device) {
    if (device is! DesktopUsbDiscoveredDevice) {
      throw UnsupportedError('Windows USB transport requires serial device');
    }
    return WindowsUsbTransport.create(device);
  }
}

class WindowsUsbTransport extends SerialUsbTransportBase {
  WindowsUsbTransport._(
    super.isolate,
    super.eventPort,
    super.events,
    super.commandPort,
  );

  static Future<WindowsUsbTransport> create(DesktopUsbDiscoveredDevice device) {
    return SerialUsbTransportBase.createFor(device, WindowsUsbTransport._);
  }
}
