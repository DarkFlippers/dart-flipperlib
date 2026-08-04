part of '../flipper_client.dart';

class _WindowsBlePlatform extends _UniversalBlePlatformBase {
  const _WindowsBlePlatform();

  @override
  Future<void> requestPermissions() async {
    try {
      await uble.UniversalBle.requestPermissions();
    } catch (e) {
      Log.error(
        '[FlipperClient] Windows BLE permission request failed: $e',
      );
    }
  }

  @override
  Future<_Transport> openTransport(BleDiscoveredDevice device) {
    return _WindowsBleTransport.create(device);
  }
}

class _WindowsBleTransport extends _UniversalBleTransportBase {
  _WindowsBleTransport._(BleDiscoveredDevice device)
    : super(device, _UniversalBleOps());

  static Future<_WindowsBleTransport> create(BleDiscoveredDevice device) async {
    final transport = _WindowsBleTransport._(device);
    await transport._configure();
    return transport;
  }
}
