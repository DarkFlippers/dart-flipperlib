import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:universal_ble/universal_ble.dart' as uble;

import '../../common/log.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'link.dart';
import 'ops.dart';
import 'platform.dart';

/// Where the kernel lists Bluetooth controllers. One entry per `hciN`.
///
/// Created by the `bluetooth` module and populated by the HCI driver, so on a
/// machine that never loads it - a VM, a server, a desktop with the radio
/// stripped - it is absent rather than empty. Both answers mean the same thing
/// here. Nothing outside this file needs it.
const String _sysClassBluetooth = '/sys/class/bluetooth';

/// Whether this machine has a Bluetooth controller, read from the kernel.
typedef HasBluetoothAdapter = bool Function();

/// Said once per isolate each, not once per call: see [LinuxBlePlatform].
///
/// Both conditions are properties of the machine rather than of the call, and
/// `availabilityState` runs per scan, per connect and on every resume re-read.
/// Nothing else can fold them: `Log` here folds nothing at all, and the app's
/// `LogService._isNewLine` only drops a *consecutive* identical body, which one
/// interleaved line from anywhere else defeats. These are `warn`, which the app
/// keeps in release, so an unlatched one is Sentry volume - the shape of the
/// burst that client-discarded two errors in three.
bool _saidNoController = false;
bool _saidCannotRead = false;

/// How the entries under a controller directory are read. Only
/// [hasAdapterIn] uses it, and only a test passes it.
typedef ListEntries = Iterable<FileSystemEntity> Function(Directory dir);

Iterable<FileSystemEntity> _listSync(Directory dir) =>
    dir.listSync(followLinks: false);

/// [sysfsHasAdapter] against an arbitrary directory, so the answers it can
/// give are reachable from a test. The real path is a property of the host and
/// no test can arrange for it to be missing.
///
/// [list] exists for one of those answers: a directory that can be stat-ed and
/// not listed cannot be arranged portably - it wants an ACL on Windows and a
/// mount namespace on Linux - and it is the answer that turns this guard off,
/// so it is the last one that should go untested.
@visibleForTesting
bool hasAdapterIn(Directory dir, {ListEntries list = _listSync}) {
  try {
    // Absent is the answer, and it is asked inside the `try` rather than
    // before it on purpose. `Directory.existsSync` does **not** fold every
    // failure into `false`: `dart:io` maps ENOENT / ENOTDIR / ENAMETOOLONG to
    // `false`, and EACCES and friends to an `OSError` that it raises as a
    // `FileSystemException` (`directory_impl.dart`, `existsSync`). A stat we
    // were not allowed to make is not a machine without a radio, and it must
    // reach the arm below rather than this `return`.
    if (!dir.existsSync()) return false;
    return list(dir).isNotEmpty;
  } on IOException catch (e) {
    // The directory is there, or might be, and will not be read: /sys masked
    // in a Flatpak or Snap confinement, a unit with ProtectKernelTunables,
    // an SELinux denial. Nothing here tells that apart from a machine with a
    // radio, and the two wrong answers are not equal - answering "no
    // adapter" switches Bluetooth off for a machine that has one, so this
    // answers the other way and lets the plugin decide, which is what every
    // other platform does unconditionally.
    //
    // Said out loud because this arm turns the guard off, and the call it
    // hands over to is the one whose failure is not catchable. If this app
    // dies of QUNLEASHED-Q again, this line is the difference between "the
    // fix did not work" and "the fix could not see /sys" - and because it is
    // emitted moments before, it arrives as a breadcrumb on that very event.
    //
    // Once, like its sibling: a masked /sys does not unmask, and the crash
    // this breadcrumb explains happens on the first delegated call, which is
    // immediately after the first of these.
    if (!_saidCannotRead) {
      Log.warn(
        '[FlipperClient] Linux: cannot read ${dir.path} ($e); '
        'asking the plugin anyway',
      );
      // After the emit, not before: `Log.warn` is a no-op while `Log.sink` is
      // null, and the sink is installed by `LogService.initialize()` inside
      // `_initCore`. Setting the flag first would latch the line away for the
      // isolate without ever having said it.
      _saidCannotRead = true;
    }
    return true;
  }
}

/// The default [HasBluetoothAdapter]: what the kernel says about this machine.
bool sysfsHasAdapter() => hasAdapterIn(Directory(_sysClassBluetooth));

class LinuxBlePlatform extends UniversalBlePlatformBase {
  const LinuxBlePlatform({this.hasAdapter = sysfsHasAdapter});

  /// Passed in so a test can answer for a machine it is not running on.
  final HasBluetoothAdapter hasAdapter;

  @override
  String get platformLabel => 'Linux';

  /// Answers from the kernel when there is no controller, without waking the
  /// plugin.
  ///
  /// universal_ble's Linux backend talks to bluez over D-Bus and initialises
  /// on first use. When that initialisation fails it does two things, and only
  /// one of them is a failure anybody can catch: it `rethrow`s, which
  /// [readAccess] already caught and reported, **and** it completes its own
  /// `_initializationCompleter` with the same error. Nothing is listening to
  /// that completer at the moment it rejects - only a later caller awaits it,
  /// and the catch does not clear it - so the first failure's rejection has no
  /// listener and goes to the root zone, which in this app is
  /// `PlatformDispatcher.onError`, which is a crash report. No `try` at this
  /// call site can reach it. That is why this one does not try: a machine with
  /// no controller is answered before the call is made.
  ///
  /// What that covers is a machine with **no controller**, which is what both
  /// reported machines were (QUNLEASHED-Q on Debian, QUNLEASHED-C the same
  /// cause under an older dbus). It is worth being exact about the subset,
  /// because the error those events carried is about bluez being absent and
  /// `hciN` is created by the kernel, not by bluez: a machine with a radio and
  /// no bluez installed still reaches the plugin and still leaks.
  ///
  /// Closing *that* does not belong here, and naming the wrong remedy is worse
  /// than naming none. A zone around [askPluginForAvailability] would be
  /// general over causes and not over call sites: the completer is created
  /// inside the backend's own initialisation, so a zone here catches the
  /// orphan only when this call is the first touch, and `startScan` or
  /// `stopScan` getting there first would walk straight past it. The
  /// containment that is general over both is a root-handler that classifies
  /// instead of treating every root-zone error as fatal - which is the app's
  /// `PlatformDispatcher.onError`, not this package, and is also why
  /// flipperlib has never needed a zone beside `guarded`.
  ///
  /// None of which this read depends on. It answers locally a question the
  /// kernel can answer without a D-Bus round trip, and on a machine that will
  /// never have a radio it also skips the backend's ten-times-100ms adapter
  /// poll and `FlipperClient.bleAvailabilityWait`. It stands on that whether
  /// or not the handler ever changes.
  ///
  /// [uble.AvailabilityState.unsupported] is the honest answer and already
  /// maps to [BleAccess.unsupported], which raises no notice - there is
  /// nothing for the user to grant or switch on.
  @override
  Future<uble.AvailabilityState> availabilityState() async {
    if (!hasAdapter()) {
      if (!_saidNoController) {
        // `warn` and not `info`, and this is not a style choice: the app pins
        // this library's level at `LogService._keptFrom`, which is `warning`,
        // so an `info` is dropped outright in a release build without a
        // breadcrumb reader and is a breadcrumb at best with one. Before this
        // method existed the same condition reached `readAccess`'s catch and
        // was reported at `error`. Downgrading it to `info` would have traded
        // a crash for no record at all - and this line is the whole
        // explanation for a BLE surface that finds nothing, which is the
        // failure mode #351 is about.
        //
        // Once per isolate: this is a property of the machine, not of the
        // call, and `availabilityState` runs per scan, per connect and on
        // every resume re-read.
        Log.warn(
          '[FlipperClient] Linux: no Bluetooth controller in '
          '$_sysClassBluetooth; BLE is unavailable on this machine',
        );
        // Set after the emit; see the sibling in `hasAdapterIn`.
        _saidNoController = true;
      }
      return uble.AvailabilityState.unsupported;
    }
    return askPluginForAvailability();
  }

  @override
  Future<Transport> openTransport(BleDiscoveredDevice device) {
    return LinuxBleTransport.create(device);
  }
}

/// Lets a test start from a known state; nothing resets a static by itself.
@visibleForTesting
void debugResetLinuxBleNotices() {
  _saidNoController = false;
  _saidCannotRead = false;
}

class LinuxBleTransport extends UniversalBleTransportBase {
  LinuxBleTransport._(BleDiscoveredDevice device)
    : super(device, UniversalBleOps());

  static Future<LinuxBleTransport> create(BleDiscoveredDevice device) async {
    final transport = LinuxBleTransport._(device);
    await transport.configure();
    return transport;
  }
}
