import 'dart:io';

import 'package:universal_ble/universal_ble.dart' as uble;

import 'android.dart';
import 'ios.dart';
import 'linux.dart';
import 'macos.dart';
import 'platform.dart';
import 'unsupported.dart';
import 'windows.dart';

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
  // Every plugin command in a single queue, as it was through universal_ble
  // 2.x. 3.0.0 changed the default to `QueueType.auto`: a per-device queue on
  // Android, Linux and Web, and *parallel* on Apple and Windows. This library
  // has its own ordered request queue above GATT - priority, seq,
  // interleavable, holdsTxUntilAnswer - but it has only ever run on top of a
  // plugin that serialised globally, and a version bump is the wrong change
  // to discover what parallel costs a link that is already sensitive to write
  // ordering. Moving to `auto` is a change of its own, with its own testing
  // on a real device per platform.
  //
  // What it costs, since the choice is ours: one queue means a command waits
  // behind every other device's, and the queue *wait* is unbounded - only
  // execution is bounded. `_pairingOpTimeout` is five minutes, so a link
  // sitting in a PIN prompt holds up the other sessions' commands for as long
  // as it lasts. `auto`'s per-device queue is the answer to that, and taking
  // it is the separate change.
  //
  // Dart-side state only, read from universal_ble 3.2.0: the setter assigns
  // to the command queue object's field and logs at a level that is `none`
  // unless a debug build raised it, and the queue is a lazy static whose
  // `isAddressSupplier` closure is not called at construction - so nothing
  // here reads `_platform`. That makes it safe on a Linux host where bluez
  // cannot start, where a call that did reach the backend would orphan a
  // rejection and be filed as a fatal crash (#443).
  uble.UniversalBle.queueType = uble.QueueType.global;
  return createBlePlatform();
}

BlePlatform createBlePlatform() {
  if (Platform.isAndroid) return const AndroidBlePlatform();
  if (Platform.isIOS) return const IosBlePlatform();
  if (Platform.isLinux) return const LinuxBlePlatform();
  if (Platform.isMacOS) return MacosBlePlatform();
  if (Platform.isWindows) return const WindowsBlePlatform();
  return const UnsupportedBlePlatform();
}
