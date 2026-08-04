part of '../flipper_client.dart';

class _MacosBlePlatform extends _UniversalBlePlatformBase {
  _MacosBlePlatform();

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
        withServices: const [FlipperClient.bleServiceUuid],
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
  Future<_Transport> openTransport(BleDiscoveredDevice device) {
    return _MacosBleTransport.create(device);
  }
}

class _MacosBleTransport extends _UniversalBleTransportBase {
  // Route the whole connection through universal_ble (one CBCentralManager for
  // the entire process). Scanning, availability and getSystemDevices already go
  // through universal_ble; the native FlipperBlePlugin only ever supplied this
  // transport's GATT ops, which meant two CBCentralManager instances coexisted.
  // Apple discourages that — the two managers fight over connection-event
  // scheduling and the link drops with spurious supervision timeouts
  // ("connection timed out unexpectedly") even while completely idle. Using the
  // same central that scanned keeps a single owner of the link.
  _MacosBleTransport._(BleDiscoveredDevice device)
    : super(device, _UniversalBleOps());

  static Future<_MacosBleTransport> create(BleDiscoveredDevice device) async {
    final transport = _MacosBleTransport._(device);
    // _configure releases the platform link itself if it fails.
    await transport._configure();
    // macOS auto-negotiates MTU. If the plugin reports the default payload,
    // fall back to the stable payload cap (see _maxBleMtuSize).
    if (transport._bleMtuSize < 100) {
      transport._bleMtuSize = _UniversalBleTransportBase._maxBleMtuSize;
      Log.info(
        '[BLE] macOS: MTU not negotiated, using mtu=${transport._bleMtuSize}',
      );
    }
    return transport;
  }

  @override
  Future<void> _openExtra() async {
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
