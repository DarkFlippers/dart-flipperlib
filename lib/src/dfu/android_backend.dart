// Android DFU host, main isolate only. UsbManager is the sole owner of the
// device: the Kotlin side (android/.../FlipperlibPlugin.kt) enumerates, asks
// for permission, opens the connection and hands over its file descriptor;
// libusb in the recovery isolate wraps that descriptor. Attach / detach are
// system broadcasts, so presence is event-driven.
//
// Platform channels are bound to the isolate that created them, and a single
// EventChannel can serve one subscriber — so this backend lives on the main
// isolate and the recovery isolate reaches it through DfuProxyClient.
import 'dart:async';

import 'package:flutter/services.dart';

import '../common/log.dart';
import 'backend.dart';

class AndroidDfuBackend implements DfuUsbBackend {
  AndroidDfuBackend({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('flipperlib/dfu'),
      _events = events ?? const EventChannel('flipperlib/dfu/events');

  final MethodChannel _methods;
  final EventChannel _events;

  late final StreamController<bool> _presence =
      StreamController<bool>.broadcast(
        onListen: _subscribe,
        onCancel: _unsubscribe,
      );
  StreamSubscription<dynamic>? _eventsSub;
  bool? _last;

  @override
  bool get available => true;

  @override
  Future<bool> isPresent() async =>
      await _methods.invokeMethod<bool>('isPresent') ?? false;

  @override
  Stream<bool> get presence => _presence.stream;

  @override
  Future<bool> waitPresence(bool present, Duration timeout) async {
    // Subscribe before querying so a transition between the two is not lost.
    final completer = Completer<bool>();
    final sub = _presence.stream.listen((value) {
      if (value == present && !completer.isCompleted) completer.complete(true);
    });
    try {
      if (await isPresent() == present) return true;
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<DfuDeviceRef?> acquire() async {
    try {
      final reply = await _methods.invokeMapMethod<String, Object?>('open');
      final fd = reply?['fd'];
      if (fd is! int) {
        throw const DfuHostException(
          DfuHostFailure.other,
          'USB host returned no file descriptor',
        );
      }
      return UsbFdDeviceRef(fd);
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'no_device':
          return null;
        case 'permission_denied':
          throw DfuHostException(
            DfuHostFailure.permissionDenied,
            e.message ?? 'USB permission denied',
          );
        default:
          throw DfuHostException(
            DfuHostFailure.other,
            '${e.code}: ${e.message ?? 'USB open failed'}',
          );
      }
    }
  }

  @override
  Future<void> release(DfuDeviceRef ref) async {
    if (ref is! UsbFdDeviceRef) {
      throw ArgumentError('AndroidDfuBackend can not release $ref');
    }
    await _methods.invokeMethod<void>('close', {'fd': ref.fd});
  }

  /// Drops whatever connection the host still holds — used when the recovery
  /// isolate is killed and can not release its device itself.
  Future<void> closeAll() async {
    try {
      await _methods.invokeMethod<void>('closeAll');
    } on PlatformException catch (e) {
      Log.error('[DFU] closeAll failed: ${e.message}');
    }
  }

  void _subscribe() {
    _last = null;
    _eventsSub = _events.receiveBroadcastStream().listen(
      (dynamic value) {
        if (value is! bool || value == _last) return;
        _last = value;
        _presence.add(value);
      },
      onError: (Object e) {
        Log.error('[DFU] Android presence stream error: $e');
      },
    );
  }

  void _unsubscribe() {
    _eventsSub?.cancel();
    _eventsSub = null;
    _last = null;
  }
}
