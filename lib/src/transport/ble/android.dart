import 'package:universal_ble/universal_ble.dart' as uble;

import '../../common/log.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'link.dart';
import 'ops.dart';
import 'platform.dart';

class AndroidBlePlatform extends UniversalBlePlatformBase {
  const AndroidBlePlatform();

  @override
  Future<void> requestPermissions() async {
    try {
      await uble.UniversalBle.requestPermissions(withAndroidFineLocation: true);
    } catch (e) {
      Log.error(
        '[FlipperClient] Android BLE permission request failed: $e',
      );
    }
  }

  @override
  Future<Transport> openTransport(BleDiscoveredDevice device) {
    return AndroidBleTransport.create(device);
  }
}

class AndroidBleTransport extends UniversalBleTransportBase {
  AndroidBleTransport._(BleDiscoveredDevice device)
    : super(device, UniversalBleOps());

  static Future<AndroidBleTransport> create(BleDiscoveredDevice device) async {
    final transport = AndroidBleTransport._(device);
    await transport.configure();
    return transport;
  }
}
