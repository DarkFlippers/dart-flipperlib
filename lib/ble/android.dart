part of '../flipper_client.dart';

class _AndroidBlePlatform extends _UniversalBlePlatformBase {
  const _AndroidBlePlatform();

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
  Future<_Transport> openTransport(BleDiscoveredDevice device) {
    return _AndroidBleTransport.create(device);
  }
}

class _AndroidBleTransport extends _UniversalBleTransportBase {
  _AndroidBleTransport._(BleDiscoveredDevice device)
    : super(device, _UniversalBleOps());

  static Future<_AndroidBleTransport> create(BleDiscoveredDevice device) async {
    final transport = _AndroidBleTransport._(device);
    await transport._configure();
    return transport;
  }
}
