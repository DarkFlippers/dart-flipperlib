part of '../flipper_client.dart';

class _LinuxBlePlatform extends _UniversalBlePlatformBase {
  const _LinuxBlePlatform();

  @override
  Future<void> requestPermissions() async {
    try {
      await uble.UniversalBle.requestPermissions();
    } catch (e) {
      Log.error('[FlipperClient] Linux BLE permission request failed: $e');
    }
  }

  @override
  Future<_Transport> openTransport(BleDiscoveredDevice device) {
    return _LinuxBleTransport.create(device);
  }
}

class _LinuxBleTransport extends _UniversalBleTransportBase {
  _LinuxBleTransport._(BleDiscoveredDevice device)
    : super(device, _UniversalBleOps());

  static Future<_LinuxBleTransport> create(BleDiscoveredDevice device) async {
    final transport = _LinuxBleTransport._(device);
    await transport._configure();
    return transport;
  }
}
