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

  static Future<MacosBleTransport> create(BleDiscoveredDevice device) async {
    final transport = MacosBleTransport._(device);
    // configure releases the platform link itself if it fails.
    await transport.configure();
    // macOS auto-negotiates MTU. If the plugin reports the default payload,
    // fall back to the stable payload cap (see maxBleMtuSize).
    if (transport.bleMtuSize < 100) {
      transport.bleMtuSize = UniversalBleTransportBase.maxBleMtuSize;
      Log.info(
        '[BLE] macOS: MTU not negotiated, using mtu=${transport.bleMtuSize}',
      );
    }
    return transport;
  }

  @override
  Future<void> openExtra() async {
    // After all subscriptions are registered, pause before sending any RPC data.
    // This gives the Flipper firmware time to send an L2CAP Connection Parameter
    // Update Request; macOS accepts it and negotiates a shorter connection interval
    // (typically 15–30 ms vs the 100 ms macOS default).  btleplug uses the same
    // 300 ms settle for exactly this reason.  The pause is harmless — it is well
    // below the BLE supervision timeout and no GATT operations are in flight.
    await Future.delayed(const Duration(milliseconds: 300));
    Log.info('[BLE] macOS: connection parameter settle complete');
  }
}
