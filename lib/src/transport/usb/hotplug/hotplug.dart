import 'dart:io';

import '../../../common/log.dart';
import 'hotplug_linux.dart';
import 'hotplug_macos.dart';
import 'hotplug_windows.dart';

/// Event-driven serial/USB attach-detach notifications straight from the OS —
/// IOKit on macOS, udev on Linux, WM_DEVICECHANGE on Windows. Each watcher
/// emits a bare signal on any serial-port topology change; consumers
/// re-enumerate. Replaces timer polling of the port list.
abstract class UsbHotplugWatcher {
  /// Arms the native notifier, routing every change to [onEvent] (delivered on
  /// the main isolate). Returns false when the notifier could not be armed, so
  /// the caller can fall back to polling.
  bool start(void Function() onEvent);

  void stop();
}

UsbHotplugWatcher? createUsbHotplugWatcher() {
  try {
    if (Platform.isMacOS) return MacosHotplugWatcher();
    if (Platform.isLinux) return LinuxHotplugWatcher();
    if (Platform.isWindows) return WindowsHotplugWatcher();
  } catch (e) {
    Log.error('[USB] native hotplug watcher unavailable: $e');
  }
  return null;
}
