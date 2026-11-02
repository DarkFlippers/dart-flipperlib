import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
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
/// Every one is a property of the machine rather than of the call, and
/// `availabilityState` runs per scan, per connect and on every resume re-read.
/// Nothing else can fold them: `Log` here folds nothing at all, and the app's
/// `LogService._isNewLine` only drops a *consecutive* identical body, which one
/// interleaved line from anywhere else defeats. These are `warn`, which the app
/// keeps in release, so an unlatched one is Sentry volume - the shape of the
/// burst that client-discarded two errors in three.
///
/// A flag each rather than one shared: they are different facts about
/// different reads, and a shared one would make any line's absence depend on
/// another's history, including across the cases of one test file.
bool _saidNoController = false;
bool _saidCannotRead = false;
bool _saidNoBluez = false;
bool _saidBluezSilent = false;

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

/// The bus name universal_ble's backend talks to. `BlueZClient.connect()`
/// addresses it, so every call that reaches `_ensureInitialized` reaches this
/// name. Nothing outside this file needs it.
const String _bluezBusName = 'org.bluez';

/// How long the bus is given to answer whether it can start [_bluezBusName].
///
/// It bounds a wait and not an answer: the timeout arm hands over to the
/// plugin, whose own activation was unbounded before this probe existed and
/// still is after it. Two seconds is three orders of magnitude longer than a
/// reply from a bus with the daemon already running, and shorter than the scan
/// the caller is about to ask for.
const Duration _bluezStartWindow = Duration(seconds: 2);

/// Whether BlueZ can be brought up on the system bus.
typedef CanReachBlueZ = Future<bool> Function();

/// How the bus is asked. Only [canReachBlueZVia] uses it, and only a test
/// passes it.
typedef StartBusService = Future<DBusStartServiceByNameReply> Function(
  String name,
);

/// [dbusCanReachBlueZ] against an arbitrary bus call, so the answers it can
/// give are reachable from a test.
///
/// The real bus is a property of the host: no test can arrange for it to be
/// absent, and none can arrange for the one state that matters here - present,
/// with an activation entry for [_bluezBusName] that cannot be honoured.
///
/// [window] is the second thing only a test passes, and for the same reason as
/// [hasAdapterIn]'s `list`: the arm it reaches is the one that turns this guard
/// off, so it is the last one that should go untested, and waiting out
/// [_bluezStartWindow] to reach it would put two seconds into the suite.
@visibleForTesting
Future<bool> canReachBlueZVia(
  StartBusService start, {
  Duration window = _bluezStartWindow,
}) async {
  try {
    // The reply code is discarded on purpose. `success` and `alreadyRunning`
    // are the same news - the name is there and can own the bus - and what
    // separates them is who started the daemon, which is not a question this
    // asks.
    await start(_bluezBusName).timeout(window);
    return true;
  } on TimeoutException {
    // Fails open, like `hasAdapterIn`'s unreadable arm and for its reason: no
    // answer is not an answer, and the wrong one here switches Bluetooth off
    // for a machine that has it. The fault this probe exists for arrives as an
    // error reply within a millisecond, never as silence.
    //
    // Said out loud because this arm hands over to the call whose failure is
    // not catchable, and because it is emitted moments before, it arrives as a
    // breadcrumb on that very event.
    if (!_saidBluezSilent) {
      Log.warn(
        '[FlipperClient] Linux: the system bus did not say whether '
        '$_bluezBusName can start within ${window.inMilliseconds}ms; asking '
        'the plugin anyway',
      );
      // After the emit, not before; see the siblings in `hasAdapterIn`.
      _saidBluezSilent = true;
    }
    return true;
  } catch (e) {
    // Every other failure is a no, and deliberately not classified further.
    // `NameHasNoOwner` with "unknown unit" is what QUNLEASHED-C carried and
    // `Spawn.ServiceNotFound` is what a bus with no entry at all answers, but
    // the useful property is not the error's name - it is that this call and
    // the plugin's first call address the same name on the same bus, so a bus
    // that will not produce [_bluezBusName] for us will not produce it for the
    // backend either. Matching on the name would narrow a general answer down
    // to the two reports we happen to have, and ADR 0008 asks for
    // classification where a caller acts on the kind; nothing here does.
    //
    // Catches [Object] and not [Exception]: a throw escaping this function
    // rejects `availabilityState`, and on the first call that is the orphan
    // this file exists to prevent.
    if (!_saidNoBluez) {
      Log.warn(
        '[FlipperClient] Linux: $_bluezBusName will not start on the system '
        'bus ($e); BLE is unavailable on this machine',
      );
      _saidNoBluez = true;
    }
    return false;
  }
}

/// The default [CanReachBlueZ]: what the system bus says about BlueZ.
///
/// `StartServiceByName` and not `NameHasOwner` or `ListActivatableNames`,
/// because neither of those separates the host this exists for from a healthy
/// one. BlueZ is bus-activatable, so on a machine where the daemon is merely
/// not running `NameHasOwner` is false and the plugin would have worked
/// anyway; and the reported host *has* an activation entry - its error was
/// `NameHasNoOwner: ... activation request failed: unknown unit`, which is the
/// bus finding that entry and systemd having no such unit - so
/// `ListActivatableNames` contains the name there too. Asking the bus to
/// actually start it is the only question whose answer differs, and on a
/// machine where the daemon is up it is one round trip that answers
/// `alreadyRunning` without starting anything.
///
/// Its own client rather than the plugin's, which is the whole point: this
/// future is ours, so its rejection has a listener and is catchable, where the
/// backend's `_initializationCompleter` rejection has neither.
Future<bool> dbusCanReachBlueZ() async {
  final bus = DBusClient.system();
  try {
    return await canReachBlueZVia(bus.startServiceByName);
  } finally {
    try {
      await bus.close();
    } catch (_) {
      // Best effort, and the kind CLAUDE.md keeps: the answer above is already
      // decided, nothing is waiting on the socket, and a throw out of a
      // `finally` would replace that answer with the uncatchable failure this
      // file exists to avoid.
    }
  }
}

class LinuxBlePlatform extends UniversalBlePlatformBase {
  const LinuxBlePlatform({
    this.hasAdapter = sysfsHasAdapter,
    this.canReachBlueZ = dbusCanReachBlueZ,
  });

  /// Passed in so a test can answer for a machine it is not running on.
  final HasBluetoothAdapter hasAdapter;

  /// The other half of the same question, passed in for the same reason.
  final CanReachBlueZ canReachBlueZ;

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
  /// **Two preconditions, because one of them was not enough.** The kernel
  /// read covers a machine with no controller, which is what the first
  /// reported machine was. It cannot cover the second: `hciN` is created by
  /// the kernel and `org.bluez` by a package, so a host with a radio and no
  /// BlueZ passes the kernel read, reaches the plugin and still leaks. That is
  /// QUNLEASHED-C, and this method's own comment named the hole for three
  /// weeks before [canReachBlueZ] closed it (#443).
  ///
  /// So the second precondition asks the bus the question the backend is about
  /// to ask it, from a client of our own - see [dbusCanReachBlueZ] for why
  /// that is the one phrasing that separates this host from a healthy one.
  /// Owning the client is what makes it safe: the rejection is on a future
  /// something is awaiting, so it is caught here rather than orphaned there.
  ///
  /// Neither is a `try` around [askPluginForAvailability], and that is not an
  /// oversight. A zone there would be general over causes and not over call
  /// sites: the completer is created inside the backend's own initialisation,
  /// so a zone here catches the orphan only when this call is the first touch,
  /// and `startScan` or `stopScan` getting there first would walk past it.
  /// (Today they cannot - `plugin_reach_guard_test.dart` pins that every
  /// initialising call sits below an availability read - but a guard on
  /// position is a weaker thing to rest on than a gate that answers.) The
  /// containment that is general over both is a root handler that classifies
  /// instead of treating every root-zone error as fatal, which is the app's
  /// `PlatformDispatcher.onError`, not this package, and is also why
  /// flipperlib has never needed a zone beside `guarded`.
  ///
  /// What is left after both gates is a bus that produced `org.bluez` and a
  /// backend that failed anyway - `_waitForAdapter` polls ten times at 100 ms
  /// and throws `Bluetooth adapter unavailable` down the identical path. That
  /// residue is the root handler's, and these gates stand whether or not it
  /// ever changes: they answer locally, and on a machine that will never have
  /// a radio they also skip that poll and `FlipperClient.bleAvailabilityWait`.
  ///
  /// [uble.AvailabilityState.unsupported] is the honest answer for both and
  /// already maps to [BleAccess.unsupported], which raises no notice. For the
  /// kernel arm that is exactly right - there is nothing to grant or switch
  /// on. For the BlueZ arm it is the closest value that exists and it
  /// understates the case: installing `bluez` would fix that machine, and
  /// saying so wants a [BleAccess] member and a UI surface that do not exist
  /// yet. The `warn` line names it in the meantime.
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
    // Awaited before the delegation and not beside it: the point is that
    // nothing touches the backend until the bus has agreed it can produce
    // `org.bluez`. The line that says why is in [canReachBlueZVia], which is
    // where the bus's own words are.
    if (!await canReachBlueZ()) return uble.AvailabilityState.unsupported;
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
  _saidNoBluez = false;
  _saidBluezSilent = false;
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
