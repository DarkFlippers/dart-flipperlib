part of '../flipper_client.dart';

class _WindowsUsbPlatform extends _SerialUsbPlatformBase {
  const _WindowsUsbPlatform();

  @override
  Future<List<FlipperDevice>> loadDevices() async {
    return comportsDevices(windowsComports);
  }

  @override
  Future<_Transport> openTransport(UsbDiscoveredDevice device) {
    if (device is! DesktopUsbDiscoveredDevice) {
      throw UnsupportedError('Windows USB transport requires serial device');
    }
    return _WindowsUsbTransport.create(device);
  }
}

class _WindowsUsbTransport extends _SerialUsbTransportBase {
  _WindowsUsbTransport._(
    super.isolate,
    super.eventPort,
    super.events,
    super.commandPort,
  );

  static Future<_WindowsUsbTransport> create(
    DesktopUsbDiscoveredDevice device,
  ) {
    return _SerialUsbTransportBase.createFor(device, _WindowsUsbTransport._);
  }
}
