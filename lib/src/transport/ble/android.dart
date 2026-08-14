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
      await uble.UniversalBle.requestPermissions(
        withAndroidFineLocation: false,
      );
    } catch (e) {
      Log.error('[FlipperClient] Android BLE permission request failed: $e');
    }
  }

  // No withServices filter: unlike iOS, Android resolves it from a service
  // cache that is empty in a fresh process — exactly when this lookup matters.
  // includeDevice filters by the Flipper MAC OUI / name instead.
  @override
  Future<List<BleDiscoveredDevice>> loadKnownDevices() async {
    try {
      final devices = await uble.UniversalBle.getSystemDevices();
      return devices
          .map(BleDiscoveredDevice.new)
          .where(includeDevice)
          .toList(growable: false);
    } catch (e) {
      Log.error('[FlipperClient] known BLE devices lookup failed: $e');
      return const <BleDiscoveredDevice>[];
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
