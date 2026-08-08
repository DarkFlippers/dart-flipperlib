import 'dart:async';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../../common/log.dart';
import 'hotplug/hotplug.dart';
import 'serial/flipper_filter.dart';
import 'serial/port_info.dart';
import '../../model/device.dart';
import '../../model/discovered.dart';
import '../../model/enums.dart';
import '../transport.dart';

abstract class UsbPlatform {
  const UsbPlatform();
  static const int flipperVid = 0x0483;
  static const int flipperPid = 0x5740;

  Future<List<FlipperDevice>> loadDevices();

  Future<Transport> openTransport(UsbDiscoveredDevice device);
  Stream<void> get usbEvents => const Stream<void>.empty();
  bool includeDevice(FlipperDevice device) {
    if (device.vendorId == flipperVid && device.productId == flipperPid) {
      return true;
    }

    final source = device.source;
    final haystack = [
      device.id,
      device.name,
      device.serialNumber ?? '',
      if (source is DesktopUsbDiscoveredDevice) source.description,
    ].join(' ').toLowerCase();
    return haystack.contains('flipper') || haystack.contains('flip_');
  }
}

class DesktopUsbEvents {
  DesktopUsbEvents._();
  static final DesktopUsbEvents instance = DesktopUsbEvents._();

  static const Duration _pollInterval = Duration(milliseconds: 400);

  late final StreamController<void> _ctrl = StreamController<void>.broadcast(
    onListen: _start,
    onCancel: _stop,
  );
  UsbHotplugWatcher? _watcher;
  Timer? _timer;
  List<String> _lastPorts = const [];

  Stream<void> get events => _ctrl.stream;

  void _start() {
    final watcher = createUsbHotplugWatcher();
    if (watcher != null && watcher.start(_emit)) {
      _watcher = watcher;
      Log.info('[USB] event-driven hotplug notifications armed');
      return;
    }
    Log.error('[USB] hotplug events unavailable; polling port list');
    _lastPorts = _currentPorts();
    _timer = Timer.periodic(_pollInterval, (_) {
      final ports = _currentPorts();
      if (_sameAs(ports, _lastPorts)) return;
      _lastPorts = ports;
      _emit();
    });
  }

  void _stop() {
    _watcher?.stop();
    _watcher = null;
    _timer?.cancel();
    _timer = null;
  }

  void _emit() {
    if (!_ctrl.isClosed) _ctrl.add(null);
  }

  List<String> _currentPorts() {
    try {
      return List<String>.from(SerialPort.availablePorts);
    } catch (_) {
      return const <String>[];
    }
  }

  bool _sameAs(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

abstract class SerialUsbPlatformBase extends UsbPlatform {
  const SerialUsbPlatformBase();

  static final RegExp _flipperDescriptionPrefix = RegExp(
    r'^Flipper[\s_-]+',
    caseSensitive: false,
  );

  @override
  bool includeDevice(FlipperDevice device) {
    final source = device.source;
    if (source is! DesktopUsbDiscoveredDevice) {
      return false;
    }
    return cdcGrepFlip(
      device: source.portName,
      description: source.description,
      hwid: source.hwid,
    );
  }

  @override
  Stream<void> get usbEvents => DesktopUsbEvents.instance.events;

  FlipperDevice serialDevice(ListPortInfo info) {
    final shortName = info.description
        .replaceFirst(_flipperDescriptionPrefix, '')
        .trim();
    return FlipperDevice(
      id: info.device,
      name: shortName.isNotEmpty ? shortName : info.device,
      link: FlipperLink.usb,
      source: DesktopUsbDiscoveredDevice(
        info.device,
        info.description,
        hwid: info.hwid,
        vendorId: info.vid,
        productId: info.pid,
        serialNumber: info.serialNumber,
      ),
      vendorId: info.vid,
      productId: info.pid,
      serialNumber: info.serialNumber,
    );
  }

  List<FlipperDevice> comportsDevices(List<ListPortInfo> Function() comports) {
    try {
      return [for (final info in comports()) serialDevice(info)];
    } catch (e) {
      Log.error('[USB] comports enumeration failed: $e');
      return const [];
    }
  }
}
