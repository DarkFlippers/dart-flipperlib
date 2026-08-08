import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../../common/log.dart';
import 'hotplug.dart';

// udev netlink monitor for the "tty" subsystem, run on a background isolate
// that blocks in poll() on the monitor fd — zero CPU while idle, wakes the
// instant the kernel reports a serial device add/remove. A 250 ms poll timeout
// only bounds how fast a stop request is honoured; real events return poll
// immediately.

const int _pollin = 0x0001;

final class _Pollfd extends Struct {
  @Int32()
  external int fd;
  @Int16()
  external int events;
  @Int16()
  external int revents;
}

DynamicLibrary _openUdev() {
  for (final name in const ['libudev.so.1', 'libudev.so', 'libudev.so.0']) {
    try {
      return DynamicLibrary.open(name);
    } catch (_) {}
  }
  throw StateError('libudev not found');
}

class LinuxHotplugWatcher implements UsbHotplugWatcher {
  Isolate? _isolate;
  ReceivePort? _recv;
  SendPort? _control;
  void Function()? _onEvent;

  @override
  bool start(void Function() onEvent) {
    // Fail fast (→ polling fallback) if libudev is absent on this host.
    try {
      _openUdev();
    } catch (e) {
      Log.error('[USB] Linux udev unavailable: $e');
      return false;
    }

    _onEvent = onEvent;
    final recv = _recv = ReceivePort();
    recv.listen((msg) {
      if (msg is SendPort) {
        _control = msg;
      } else if (msg == 'error') {
        Log.error('[USB] Linux udev monitor failed to start');
      } else {
        _onEvent?.call();
      }
    });

    Isolate.spawn(_monitorEntry, recv.sendPort).then(
      (iso) {
        _isolate = iso;
      },
      onError: (Object e) {
        Log.error('[USB] Linux udev isolate spawn failed: $e');
      },
    );
    return true;
  }

  @override
  void stop() {
    _control?.send('stop');
    _control = null;
    _recv?.close();
    _recv = null;
    _onEvent = null;
    final iso = _isolate;
    _isolate = null;
    // The isolate honours 'stop' within one poll timeout and exits on its own;
    // kill after a grace period only as a backstop.
    Future<void>.delayed(const Duration(seconds: 1), () {
      iso?.kill(priority: Isolate.beforeNextEvent);
    });
  }
}

Future<void> _monitorEntry(SendPort mainSend) async {
  final control = ReceivePort();
  mainSend.send(control.sendPort);
  var stopped = false;
  control.listen((_) => stopped = true);

  final udevLib = _openUdev();
  final libc = DynamicLibrary.process();

  final udevNew = udevLib
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'udev_new',
      );
  final monitorNew = udevLib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('udev_monitor_new_from_netlink');
  final filterAdd = udevLib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
      >('udev_monitor_filter_add_match_subsystem_devtype');
  final enableReceiving = udevLib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('udev_monitor_enable_receiving');
  final getFd = udevLib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('udev_monitor_get_fd');
  final receiveDevice = udevLib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('udev_monitor_receive_device');
  final deviceUnref = udevLib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('udev_device_unref');
  final monitorUnref = udevLib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('udev_monitor_unref');
  final udevUnref = udevLib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('udev_unref');
  final poll = libc
      .lookupFunction<
        Int32 Function(Pointer<_Pollfd>, Uint64, Int32),
        int Function(Pointer<_Pollfd>, int, int)
      >('poll');

  final udev = udevNew();
  if (udev == nullptr) {
    mainSend.send('error');
    control.close();
    return;
  }

  final udevStr = 'udev'.toNativeUtf8();
  final ttyStr = 'tty'.toNativeUtf8();
  final monitor = monitorNew(udev, udevStr);
  final fds = malloc<_Pollfd>();
  try {
    if (monitor == nullptr) {
      mainSend.send('error');
      udevUnref(udev);
      control.close();
      return;
    }
    filterAdd(monitor, ttyStr, nullptr);
    enableReceiving(monitor);
    final fd = getFd(monitor);
    if (fd < 0) {
      mainSend.send('error');
      monitorUnref(monitor);
      udevUnref(udev);
      control.close();
      return;
    }

    fds.ref
      ..fd = fd
      ..events = _pollin
      ..revents = 0;

    while (!stopped) {
      final n = poll(fds, 1, 250);
      if (stopped) break;
      if (n > 0 && (fds.ref.revents & _pollin) != 0) {
        // Drain every queued device so the fd clears, then coalesce into one
        // re-enumeration signal.
        while (true) {
          final dev = receiveDevice(monitor);
          if (dev == nullptr) break;
          deviceUnref(dev);
        }
        mainSend.send(null);
      }
      // Let the control port deliver 'stop' between blocking polls.
      await Future<void>.delayed(Duration.zero);
    }
    monitorUnref(monitor);
    udevUnref(udev);
  } finally {
    malloc.free(fds);
    malloc.free(udevStr);
    malloc.free(ttyStr);
    control.close();
  }
}
