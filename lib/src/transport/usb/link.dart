import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../common/log.dart';
import '../../model/discovered.dart';
import '../../model/enums.dart';
import '../transport.dart';
import 'isolate.dart';

abstract class SerialUsbTransportBase extends Transport {
  final Isolate _isolate;
  final ReceivePort _eventPort;
  final Stream<dynamic> _events;
  final SendPort _commandPort;
  final Map<int, Completer<void>> _inFlight = {};
  final Completer<void> _exited = Completer<void>();
  StreamSubscription<dynamic>? _eventSub;
  int _writeSeq = 0;

  SerialUsbTransportBase(
    this._isolate,
    this._eventPort,
    this._events,
    this._commandPort,
  );

  static Future<T> createFor<T extends SerialUsbTransportBase>(
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
      Log.error('[FlipperClient] desktop USB fault: ${message.message}');
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
