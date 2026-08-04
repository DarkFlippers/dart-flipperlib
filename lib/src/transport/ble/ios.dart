import 'package:universal_ble/universal_ble.dart' as uble;

import '../../common/log.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'gatt.dart';
import 'link.dart';
import 'ops.dart';
import 'platform.dart';

class IosBlePlatform extends UniversalBlePlatformBase {
  const IosBlePlatform();

  @override
  Future<void> requestPermissions() async {
    try {
      await uble.UniversalBle.requestPermissions();
    } catch (e) {
      Log.error('[FlipperClient] iOS BLE permission request failed: $e');
    }
  }

  @override
  Future<List<BleDiscoveredDevice>> loadKnownDevices() async {
    try {
      final devices = await uble.UniversalBle.getSystemDevices(
        withServices: const [flipperBleServiceUuid],
      );
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
    return IosBleTransport.create(device);
  }
}

class IosBleTransport extends UniversalBleTransportBase {
  IosBleTransport._(BleDiscoveredDevice device)
    : super(device, UniversalBleOps());

  static Future<IosBleTransport> create(BleDiscoveredDevice device) async {
    final transport = IosBleTransport._(device);
    await transport.configure();
    return transport;
  }
}
