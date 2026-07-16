part of '../flipper_client.dart';

class _LinuxUsbPlatform extends _SerialUsbPlatformBase {
  const _LinuxUsbPlatform();

  @override
  Future<List<FlipperDevice>> loadDevices() async {
    return comportsDevices(linuxComports);
  }

  @override
  Future<_Transport> openTransport(UsbDiscoveredDevice device) {
    if (device is! DesktopUsbDiscoveredDevice) {
      throw UnsupportedError('Linux USB transport requires serial device');
    }
    return _LinuxUsbTransport.create(device);
  }
}

class _LinuxUsbTransport extends _SerialUsbTransportBase {
  _LinuxUsbTransport._(
    super.isolate,
    super.eventPort,
    super.events,
    super.commandPort,
  );

  static Future<_LinuxUsbTransport> create(DesktopUsbDiscoveredDevice device) {
    return _SerialUsbTransportBase.createFor(device, _LinuxUsbTransport._);
  }
}
