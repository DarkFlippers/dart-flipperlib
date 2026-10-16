import '../../model/discovered.dart';
import '../transport.dart';
import 'link.dart';
import 'ops.dart';
import 'platform.dart';

class WindowsBlePlatform extends UniversalBlePlatformBase {
  const WindowsBlePlatform();

  @override
  String get platformLabel => 'Windows';

  @override
  Future<Transport> openTransport(BleDiscoveredDevice device) {
    return WindowsBleTransport.create(device);
  }
}

class WindowsBleTransport extends UniversalBleTransportBase {
  WindowsBleTransport._(BleDiscoveredDevice device)
    : super(device, UniversalBleOps());

  static Future<WindowsBleTransport> create(BleDiscoveredDevice device) async {
    final transport = WindowsBleTransport._(device);
    await transport.configure();
    return transport;
  }
}
