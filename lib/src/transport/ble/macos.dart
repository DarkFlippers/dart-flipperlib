import 'package:universal_ble/universal_ble.dart' as uble;

import '../../common/log.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'gatt.dart';
import 'link.dart';
import 'ops.dart';
import 'platform.dart';

class MacosBlePlatform extends UniversalBlePlatformBase {
  MacosBlePlatform();

  @override
  Future<void> requestPermissions() async {
    try {
      await uble.UniversalBle.requestPermissions();
    } catch (e) {
      Log.error('[FlipperClient] macOS BLE permission request failed: $e');
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
    return MacosBleTransport.create(device);
  }
}

class MacosBleTransport extends UniversalBleTransportBase {
  // Route the whole connection through universal_ble (one CBCentralManager for
  // the entire process). Scanning, availability and getSystemDevices already go
  // through universal_ble; the native FlipperBlePlugin only ever supplied this
  // transport's GATT ops, which meant two CBCentralManager instances coexisted.
  // Apple discourages that — the two managers fight over connection-event
  // scheduling and the link drops with spurious supervision timeouts
  // ("connection timed out unexpectedly") even while completely idle. Using the
  // same central that scanned keeps a single owner of the link.
  MacosBleTransport._(BleDiscoveredDevice device)
    : super(device, UniversalBleOps());

  @override
  Duration get connectSettle => const Duration(milliseconds: 300);

  static Future<MacosBleTransport> create(BleDiscoveredDevice device) async {
    final transport = MacosBleTransport._(device);
    // configure releases the platform link itself if it fails.
    await transport.configure();
    return transport;
  }
}
