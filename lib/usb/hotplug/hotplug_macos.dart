import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../log_service.dart';
import 'usb_hotplug.dart';

// IOKit service-matching notifications on IOSerialBSDClient, delivered on a
// private dispatch queue. Every Flipper CDC port attach/detach fires the
// callback; we drain the iterator (which re-arms the notification) and signal
// a re-enumeration. No polling.

final DynamicLibrary _iokit = DynamicLibrary.open(
  '/System/Library/Frameworks/IOKit.framework/IOKit',
);
final DynamicLibrary _system = DynamicLibrary.process();

// kIOFirstMatchNotification / kIOTerminatedNotification message strings.
const String _kFirstMatch = 'IOServiceFirstMatch';
const String _kTerminated = 'IOServiceTerminate';
const String _kSerialBsdClient = 'IOSerialBSDClient';

typedef _NotifyCallbackNative = Void Function(Pointer<Void>, Uint32);

final _ioNotificationPortCreate = _iokit.lookupFunction<
    Pointer<Void> Function(Uint32),
    Pointer<Void> Function(int)>('IONotificationPortCreate');

final _ioNotificationPortSetDispatchQueue = _iokit.lookupFunction<
    Void Function(Pointer<Void>, Pointer<Void>),
    void Function(Pointer<Void>, Pointer<Void>)>(
    'IONotificationPortSetDispatchQueue');

final _ioNotificationPortDestroy = _iokit.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('IONotificationPortDestroy');

final _ioServiceMatching = _iokit.lookupFunction<
    Pointer<Void> Function(Pointer<Utf8>),
    Pointer<Void> Function(Pointer<Utf8>)>('IOServiceMatching');

final _ioServiceAddMatchingNotification = _iokit.lookupFunction<
    Int32 Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Void>,
        Pointer<NativeFunction<_NotifyCallbackNative>>,
        Pointer<Void>,
        Pointer<Uint32>),
    int Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Void>,
        Pointer<NativeFunction<_NotifyCallbackNative>>,
        Pointer<Void>,
        Pointer<Uint32>)>('IOServiceAddMatchingNotification');

final _ioIteratorNext = _iokit.lookupFunction<Uint32 Function(Uint32),
    int Function(int)>('IOIteratorNext');

final _ioObjectRelease = _iokit.lookupFunction<Int32 Function(Uint32),
    int Function(int)>('IOObjectRelease');

final _dispatchQueueCreate = _system.lookupFunction<
    Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>),
    Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>)>(
    'dispatch_queue_create');

final _dispatchRelease = _system.lookupFunction<Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('dispatch_release');

// dispatch_sync_f(queue, context, work) — runs `work(context)` on `queue` and
// blocks until it (and everything queued ahead of it) has finished. Used as a
// teardown barrier with free() as a harmless no-op work item (free(NULL)).
final _dispatchSyncF = _system.lookupFunction<
    Void Function(Pointer<Void>, Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Void>)>>),
    void Function(Pointer<Void>, Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Void>)>>)>(
    'dispatch_sync_f');

final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _freeFn =
    _system.lookup<NativeFunction<Void Function(Pointer<Void>)>>('free');

class MacosHotplugWatcher implements UsbHotplugWatcher {
  NativeCallable<_NotifyCallbackNative>? _callable;
  Pointer<Void> _notifyPort = nullptr;
  Pointer<Void> _queue = nullptr;
  final List<int> _iterators = [];
  void Function()? _onEvent;

  @override
  bool start(void Function() onEvent) {
    _onEvent = onEvent;
    try {
      _notifyPort = _ioNotificationPortCreate(0); // kIOMainPortDefault
      if (_notifyPort == nullptr) return false;

      final label = 'com.qunleashed.usb.hotplug'.toNativeUtf8();
      try {
        _queue = _dispatchQueueCreate(label, nullptr);
      } finally {
        malloc.free(label);
      }
      if (_queue == nullptr) {
        stop();
        return false;
      }
      _ioNotificationPortSetDispatchQueue(_notifyPort, _queue);

      // Callbacks fire on the dispatch queue thread; .listener marshals them
      // back onto the main isolate, where draining the iterator and touching
      // Dart state is safe.
      _callable = NativeCallable<_NotifyCallbackNative>.listener(_onNotify);

      _addNotification(_kFirstMatch);
      _addNotification(_kTerminated);
      return true;
    } catch (e) {
      LogService.log('[USB] macOS IOKit hotplug arm failed: $e');
      stop();
      return false;
    }
  }

  void _addNotification(String type) {
    // IOServiceMatching copies the class name; the returned dictionary is
    // consumed by IOServiceAddMatchingNotification, so it must not be released.
    final className = _kSerialBsdClient.toNativeUtf8();
    final typeStr = type.toNativeUtf8();
    final iterOut = malloc<Uint32>();
    try {
      final matching = _ioServiceMatching(className);
      if (matching == nullptr) {
        throw StateError('IOServiceMatching returned null');
      }
      final kr = _ioServiceAddMatchingNotification(
        _notifyPort,
        typeStr,
        matching,
        _callable!.nativeFunction,
        nullptr,
        iterOut,
      );
      if (kr != 0) {
        throw StateError('IOServiceAddMatchingNotification($type) kr=$kr');
      }
      final iterator = iterOut.value;
      _iterators.add(iterator);
      // Draining the initial matches arms the notification for future events.
      _drain(iterator);
    } finally {
      malloc.free(className);
      malloc.free(typeStr);
      malloc.free(iterOut);
    }
  }

  void _drain(int iterator) {
    while (true) {
      final obj = _ioIteratorNext(iterator);
      if (obj == 0) break;
      _ioObjectRelease(obj);
    }
  }

  void _onNotify(Pointer<Void> refcon, int iterator) {
    _drain(iterator);
    _onEvent?.call();
  }

  @override
  void stop() {
    final port = _notifyPort;
    final queue = _queue;
    _notifyPort = nullptr;
    _queue = nullptr;

    // 1. Stop delivery and cancel the dispatch source — no new callbacks after
    //    this. A callback already running or queued still completes.
    if (port != nullptr) {
      _ioNotificationPortDestroy(port);
    }
    // 2. Barrier: block until every callback the serial queue had in flight or
    //    queued has finished. Only now is it safe to free the callback — this
    //    is what prevents "callback invoked after it has been deleted".
    if (queue != nullptr) {
      try {
        _dispatchSyncF(queue, nullptr, _freeFn);
      } catch (_) {}
    }
    // 3. No callback can touch the iterators or the callable anymore.
    for (final iterator in _iterators) {
      _ioObjectRelease(iterator);
    }
    _iterators.clear();
    if (queue != nullptr) {
      try {
        _dispatchRelease(queue);
      } catch (_) {}
    }
    _callable?.close();
    _callable = null;
    _onEvent = null;
  }
}
