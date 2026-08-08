import 'package:universal_ble/universal_ble.dart' as uble;

import '../../common/log.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'link.dart';
import 'ops.dart';
import 'platform.dart';

class WindowsBlePlatform extends UniversalBlePlatformBase {
  const WindowsBlePlatform();

  @override
  Future<void> requestPermissions() async {
    try {
      await uble.UniversalBle.requestPermissions();
    } catch (e) {
      Log.error('[FlipperClient] Windows BLE permission request failed: $e');
    }
  }

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
