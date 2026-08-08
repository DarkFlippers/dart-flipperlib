import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../common/log.dart';
import 'hotplug.dart';

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

final _ioNotificationPortCreate = _iokit
    .lookupFunction<
      Pointer<Void> Function(Uint32),
      Pointer<Void> Function(int)
    >('IONotificationPortCreate');

final _ioNotificationPortSetDispatchQueue = _iokit
    .lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>)
    >('IONotificationPortSetDispatchQueue');

final _ioNotificationPortDestroy = _iokit
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'IONotificationPortDestroy',
    );

// Same symbol as a raw dispatch_function_t: void(*)(void* context). Its ABI
// (one pointer argument, no return) matches dispatch_sync_f's work function, so
// we can run the destroy *on the notifier's own queue* with the port as the
// context — serializing it with any callout already in flight.
final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
_ioNotificationPortDestroyFn = _iokit
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'IONotificationPortDestroy',
    );

final _ioServiceMatching = _iokit
    .lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>)
    >('IOServiceMatching');

final _ioServiceAddMatchingNotification = _iokit
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Void>,
        Pointer<NativeFunction<_NotifyCallbackNative>>,
        Pointer<Void>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Utf8>,
        Pointer<Void>,
        Pointer<NativeFunction<_NotifyCallbackNative>>,
        Pointer<Void>,
        Pointer<Uint32>,
      )
    >('IOServiceAddMatchingNotification');

final _ioIteratorNext = _iokit
    .lookupFunction<Uint32 Function(Uint32), int Function(int)>(
      'IOIteratorNext',
    );

final _ioObjectRelease = _iokit
    .lookupFunction<Int32 Function(Uint32), int Function(int)>(
      'IOObjectRelease',
    );

final _dispatchQueueCreate = _system
    .lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Utf8>, Pointer<Void>)
    >('dispatch_queue_create');

final _dispatchRelease = _system
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'dispatch_release',
    );

// dispatch_sync_f(queue, context, work) — runs `work(context)` on `queue` and
// blocks until it (and everything queued ahead of it) has finished. Used to run
// the notifier teardown on the notifier's own serial queue, serialized with any
// callout in flight.
final _dispatchSyncF = _system
    .lookupFunction<
      Void Function(
        Pointer<Void>,
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
      ),
      void Function(
        Pointer<Void>,
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
      )
    >('dispatch_sync_f');

class MacosHotplugWatcher implements UsbHotplugWatcher {
  NativeCallable<_NotifyCallbackNative>? _callable;
  Pointer<Void> _notifyPort = nullptr;
  Pointer<Void> _queue = nullptr;
  final List<int> _iterators = [];
  void Function()? _onEvent;
  bool _active = false;

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
      _active = true;
      return true;
    } catch (e) {
      Log.error('[USB] macOS IOKit hotplug arm failed: $e');
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
    // A .listener callback is delivered asynchronously via the isolate event
    // loop, so a message posted before stop() can still arrive after teardown.
    // The iterator has been released by then; touching it would be a
    // use-after-free, so drop late deliveries.
    if (!_active) return;
    _drain(iterator);
    _onEvent?.call();
  }

  @override
  void stop() {
    _active = false;
    final port = _notifyPort;
    final queue = _queue;
    _notifyPort = nullptr;
    _queue = nullptr;

    // Tear down the IOKit notifier so it can never invoke the FFI trampoline
    // again — this is what prevents the process-fatal "callback invoked after
    // it has been deleted" abort.
    //
    // IONotificationPortDestroy cancels the mach-recv dispatch source, but
    // dispatch_source_cancel is asynchronous. Calling destroy from *this*
    // (main-isolate) thread races the source's own drain on `queue`: a callout
    // can latch and fire after destroy returns and after any barrier we submit
    // behind it — exactly the window that produced the crash.
    //
    // The fix: run destroy *on the notifier's own serial queue* via
    // dispatch_sync (the port doubles as the dispatch_function_t context). That
    // serializes it with any callout already in flight and blocks until it
    // finishes, and the cancel it performs forecloses all future callouts.
    // Only once this returns is the trampoline provably unreachable, so
    // closing the NativeCallable below can no longer be raced.
    if (port != nullptr) {
      if (queue != nullptr) {
        try {
          _dispatchSyncF(queue, port, _ioNotificationPortDestroyFn);
        } catch (_) {
          _ioNotificationPortDestroy(port);
        }
      } else {
        _ioNotificationPortDestroy(port);
      }
    }
    // No callout can touch the iterators or the callable anymore.
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
