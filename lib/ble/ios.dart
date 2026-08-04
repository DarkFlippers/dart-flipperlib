part of '../flipper_client.dart';

class _IosBlePlatform extends _UniversalBlePlatformBase {
  const _IosBlePlatform();

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
    return _IosBleTransport.create(device);
  }
}

class _IosBleTransport extends _UniversalBleTransportBase {
  _IosBleTransport._(BleDiscoveredDevice device)
    : super(device, _UniversalBleOps());

  static Future<_IosBleTransport> create(BleDiscoveredDevice device) async {
    final transport = _IosBleTransport._(device);
    await transport._configure();
    return transport;
  }
}
