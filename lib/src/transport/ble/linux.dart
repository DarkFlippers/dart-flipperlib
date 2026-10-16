import '../../model/discovered.dart';
import '../transport.dart';
import 'link.dart';
import 'ops.dart';
import 'platform.dart';

class LinuxBlePlatform extends UniversalBlePlatformBase {
  const LinuxBlePlatform();

  @override
  String get platformLabel => 'Linux';

  @override
  Future<Transport> openTransport(BleDiscoveredDevice device) {
    return LinuxBleTransport.create(device);
  }
}

class LinuxBleTransport extends UniversalBleTransportBase {
  LinuxBleTransport._(BleDiscoveredDevice device)
    : super(device, UniversalBleOps());

  static Future<LinuxBleTransport> create(BleDiscoveredDevice device) async {
    final transport = LinuxBleTransport._(device);
    await transport.configure();
    return transport;
  }
}
