part of '../flipper_client.dart';

abstract class _UsbPlatform {
  const _UsbPlatform();
  static const int flipperVid = 0x0483;
  static const int flipperPid = 0x5740;

  Future<List<FlipperDevice>> loadDevices();

  Future<_Transport> openTransport(UsbDiscoveredDevice device);
  Stream<void> get usbEvents => const Stream<void>.empty();
  bool includeDevice(FlipperDevice device) {
    if (device.vendorId == flipperVid && device.productId == flipperPid) {
      return true;
    }

    final haystack = [
      device.id,
      device.name,
      device.serialNumber ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains('flipper') || haystack.contains('flip_');
  }
}

class _SerialPortWatcher {
  _SerialPortWatcher._();
  static final _SerialPortWatcher instance = _SerialPortWatcher._();

  static const Duration _interval = Duration(seconds: 1);

  late final StreamController<void> _ctrl = StreamController<void>.broadcast(
    onListen: _start,
    onCancel: _stop,
  );
  Timer? _timer;
  List<String> _lastPorts = const [];

  Stream<void> get events => _ctrl.stream;

  void _start() {
    _lastPorts = _currentPorts();
    _timer ??= Timer.periodic(_interval, (_) {
      final ports = _currentPorts();
      if (_sameAs(ports, _lastPorts)) return;
      _lastPorts = ports;
      _ctrl.add(null);
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
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

abstract class _SerialUsbPlatformBase extends _UsbPlatform {
  const _SerialUsbPlatformBase();

  @override
  Stream<void> get usbEvents => _SerialPortWatcher.instance.events;

  String metadataDescription(SerialPort port) =>
      _readSerialString(() => port.description) ?? '';

  int? metadataVendorId(SerialPort port) => _readSerialInt(() => port.vendorId);

  int? metadataProductId(SerialPort port) =>
      _readSerialInt(() => port.productId);

  String? metadataSerialNumber(SerialPort port) =>
      _readSerialString(() => port.serialNumber);

  FlipperDevice serialDevice(
    String portName, {
    required String description,
    required int? vendorId,
    required int? productId,
    required String? serialNumber,
  }) {
    return FlipperDevice(
      id: portName,
      name: description.isNotEmpty ? description : portName,
      link: FlipperLink.usb,
      source: DesktopUsbDiscoveredDevice(
        portName,
        description,
        vendorId: vendorId,
        productId: productId,
        serialNumber: serialNumber,
      ),
      vendorId: vendorId,
      productId: productId,
      serialNumber: serialNumber,
    );
  }

  T? _readSerialProperty<T>(T? Function() read) {
    try {
      return read();
    } catch (e) {
      LogService.log('[USB] failed to read serial port metadata: $e');
      return null;
    }
  }

  int? _readSerialInt(int? Function() read) => _readSerialProperty(read);

  String? _readSerialString(String? Function() read) =>
      _readSerialProperty(read);
}

abstract class _SerialUsbTransportBase extends _Transport {
  final Isolate _isolate;
  final ReceivePort _eventPort;
  final Stream<dynamic> _events;
  final SendPort _commandPort;
  final Map<int, Completer<void>> _inFlight = {};
  final Completer<void> _exited = Completer<void>();
  StreamSubscription<dynamic>? _eventSub;
  int _writeSeq = 0;

  _SerialUsbTransportBase(
    this._isolate,
    this._eventPort,
    this._events,
    this._commandPort,
  );

  static Future<T> createFor<T extends _SerialUsbTransportBase>(
    DesktopUsbDiscoveredDevice device,
    T Function(
      Isolate isolate,
      ReceivePort eventPort,
      Stream<dynamic> events,
      SendPort commandPort,
    )
    build,
  ) async {
    final eventPort = ReceivePort();
    final events = eventPort.asBroadcastStream();
    final boot = Completer<Object>();

    late StreamSubscription<dynamic> bootSub;
    bootSub = events.listen((message) {
      if (boot.isCompleted) return;
      if (message is DesktopUsbReady) {
        boot.complete(message);
      } else if (message is DesktopUsbFault) {
        boot.complete(message);
      }
    });

    final isolate = await Isolate.spawn<DesktopUsbIsolateConfig>(
      desktopUsbIsolateEntry,
      DesktopUsbIsolateConfig(device.portName, eventPort.sendPort),
      errorsAreFatal: false,
      debugName: 'flipper-usb-${device.portName}',
    );

    final result = await boot.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          const DesktopUsbFault('Timed out opening USB serial port'),
    );
    await bootSub.cancel();

    if (result is DesktopUsbFault) {
      isolate.kill(priority: Isolate.immediate);
      eventPort.close();
      throw StateError(result.message);
    }
    final ready = result as DesktopUsbReady;
    return build(isolate, eventPort, events, ready.commandPort);
  }

  @override
  bool get supportsCli => true;

  @override
  FlipperMode get initialMode => FlipperMode.cli;

  @override
  int get storageChunkSize => 1024;

  @override
  Future<void> open() async {
    _eventSub = _events.listen(_onIsolateMessage);
  }

  void _onIsolateMessage(dynamic message) {
    if (message is DesktopUsbBytes) {
      addBytes(message.bytes);
    } else if (message is DesktopUsbWriteAck) {
      final pending = _inFlight.remove(message.seq);
      if (message.error != null) {
        final error = StateError('Serial write failed: ${message.error}');
        if (pending != null && !pending.isCompleted) {
          pending.completeError(error);
        }
        onTransportFault(error);
      } else {
        if (pending == null || pending.isCompleted) return;
        pending.complete();
      }
    } else if (message is DesktopUsbFault) {
      LogService.log('[FlipperClient] desktop USB fault: ${message.message}');
      onTransportFault(StateError(message.message));
    } else if (message is DesktopUsbExited) {
      if (!_exited.isCompleted) _exited.complete();
      onTransportFault(StateError('USB isolate exited'));
    }
  }

  @override
  Future<void> rawWrite(Uint8List bytes) {
    if (!isActive) {
      return Future.error(StateError('Transport closed'));
    }
    final seq = _writeSeq++;
    final completer = Completer<void>();
    _inFlight[seq] = completer;
    _commandPort.send(DesktopUsbWriteRequest(bytes, seq));
    return completer.future;
  }

  @override
  Future<void> nudgeCli() async {
    if (!isActive) {
      throw StateError('Transport closed');
    }
    _commandPort.send(const DesktopUsbDtrPulse());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await writeAscii('\r');
  }

  void _failInFlight(Object error) {
    final pending = List<Completer<void>>.from(_inFlight.values);
    _inFlight.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  @override
  void onFaultExtra(Object error) {
    _failInFlight(error);
    if (!_exited.isCompleted) _exited.complete();
  }

  @override
  Future<void> doClose() async {
    // SendPort.send to a dead isolate is a silent no-op, so no guard needed.
    _commandPort.send(const DesktopUsbShutdown());
    await _exited.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    _isolate.kill(priority: Isolate.beforeNextEvent);
    await _eventSub?.cancel();
    _eventSub = null;
    _eventPort.close();
    _failInFlight(StateError('Transport closed'));
  }
}
