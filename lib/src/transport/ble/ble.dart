import 'dart:io';

import 'package:universal_ble/universal_ble.dart' as uble;

import 'android.dart';
import 'ios.dart';
import 'linux.dart';
import 'macos.dart';
import 'platform.dart';
import 'unsupported.dart';
import 'windows.dart';

export 'device_id.dart';
export 'gatt.dart';
export 'link.dart';
export 'platform.dart';

/// This platform's BLE implementation, and the one point that configures the
/// plugin for the whole process.
///
/// A lazy top-level final, which is what makes it a usable configuration
/// point: every BLE path in this library reads `blePlatform` before it
/// touches the plugin - the scan and the direct connect both ask it for
/// availability first, which `plugin_reach_guard_test.dart` pins - so the
/// initialiser runs once and runs first.
final BlePlatform blePlatform = _configuredBlePlatform();

BlePlatform _configuredBlePlatform() {
  _serialiseBleCommands();
  return createBlePlatform();
}

/// Keeps every plugin command in a single queue, as it was through
/// universal_ble 2.x.
///
/// 3.0.0 changed the default to [uble.QueueType.auto]: a per-device queue on
/// Android, Linux and Web, and *parallel* on Apple and Windows. This library
/// has its own ordered request queue above GATT - priority, seq,
/// interleavable, holdsTxUntilAnswer - but it has only ever run on top of a
/// plugin that serialised globally, and a version bump is the wrong change to
/// discover what parallel costs a link that is already sensitive to write
/// ordering. Moving to `auto` is a change of its own, with its own testing on
/// a real device per platform.
///
/// Dart-side state only: the setter writes to the plugin's command queue
/// object and reaches no backend, so it is safe on a Linux host where bluez
/// cannot start - where a call that did reach one would orphan a rejection
/// and be filed as a fatal crash (#443).
void _serialiseBleCommands() =>
    uble.UniversalBle.queueType = uble.QueueType.global;

BlePlatform createBlePlatform() {
  if (Platform.isAndroid) return const AndroidBlePlatform();
  if (Platform.isIOS) return const IosBlePlatform();
  if (Platform.isLinux) return const LinuxBlePlatform();
  if (Platform.isMacOS) return MacosBlePlatform();
  if (Platform.isWindows) return const WindowsBlePlatform();
  return const UnsupportedBlePlatform();
}
