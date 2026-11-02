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

/// Whether the bus has already produced `org.bluez` once in this isolate.
///
/// A cache of the *positive* answer only, and the asymmetry is the whole of
/// it. The gate's protective value is spent on the first delegation: on
/// success the backend sets `isInitialized` and every later
/// `getBluetoothAvailabilityState` is an in-memory field read that cannot
/// throw, and on failure its `_initializationCompleter` is left holding the
/// error, so every later call awaits an already-rejected future and is
/// caught. Either way there is no second orphan to prevent, and re-asking the
/// bus buys nothing while costing a socket, an auth handshake and ten round
/// trips per scan, per connect and per resume - and desktop Flutter resumes
/// on window focus, so an alt-tab was a D-Bus storm.
///
/// The *negative* stays uncached, and that is not an oversight either: it is
/// what lets a host recover. Because the gate refuses before the plugin is
/// touched, the backend's one initialisation attempt is still unspent, so a
/// user who installs `bluez` gets working BLE on the next scan rather than at
/// the next launch. Caching the refusal would throw that away.
///
/// A static and not a field because [LinuxBlePlatform] is `const`; there is
/// one of it per process either way.
bool _bluezReached = false;

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
    // `warnOnce` and not a flag of this file's own: the latch has to be
    // conditioned on the line actually having gone somewhere, and five copies
    // of that rule here all got it wrong the same way. `Log.warnOnce` has the
    // argument.
    Log.warnOnce(
      'linux/sysfs-unreadable',
      '[FlipperClient] Linux: cannot read ${dir.path} ($e); '
          'asking the plugin anyway',
    );
    return true;
  }
}

/// The default [HasBluetoothAdapter]: what the kernel says about this machine.
bool sysfsHasAdapter() => hasAdapterIn(Directory(_sysClassBluetooth));

/// The bus name universal_ble's backend talks to.
///
/// `BlueZClient` is constructed with no bus of its own, so it defaults to
/// `DBusClient.system()`, and its `connect()` calls `GetManagedObjects` on
/// this name - which is the call that asks the bus to activate it. So the
/// *first* call to reach `_ensureInitialized` reaches this name on this bus,
/// and that is the only call that matters: a later one returns on
/// `isInitialized` or awaits the existing completer without connecting.
/// Nothing outside this file needs it.
const String _bluezBusName = 'org.bluez';

/// How long the bus is given to answer whether it can start [_bluezBusName].
///
/// It bounds a wait and not an answer: the timeout arm hands over to the
/// plugin, whose own activation was unbounded before this probe existed and
/// still is after it - `package:dbus` has no client-side reply timeout
/// anywhere. A reply from a bus with the daemon already running is
/// sub-millisecond, and two seconds sits well inside what the caller is about
/// to spend anyway: `scanBle` defaults to ten and `bleAvailabilityWait` is
/// five.
const Duration _bluezStartWindow = Duration(seconds: 2);

/// How long the client is given to let go of the bus.
///
/// Not tidiness; an unbounded close is a hang. `DBusClient.close()` cancels
/// the three signal subscriptions `_connect` installed, each cancel awaits a
/// `RemoveMatch` **method call**, and `package:dbus` neither times out a reply
/// nor rejects a pending call when the socket goes. So on a bus whose socket
/// is open and which has stopped answering - the one state that reaches the
/// timeout arm of [canReachBlueZVia] - an unbounded close never returns, and
/// `availabilityState` never completes.
///
/// That is worse than either answer it was deciding between. It strands the
/// client's `_enqueue` chain for the life of the chain, it sits *above*
/// `_awaitBleAvailable`'s own `.timeout`, and it hangs the app's permission
/// read inside a `Future.wait` that no catch can see, because a hang is not a
/// throw. One second is three local round trips' worth.
const Duration _bluezCloseWindow = Duration(seconds: 1);

/// Whether BlueZ can be brought up on the system bus.
typedef CanReachBlueZ = Future<bool> Function();

/// The one call the probe makes. Only [canReachBlueZVia] uses it, and only a
/// test passes it directly.
typedef StartBusService = Future<DBusStartServiceByNameReply> Function(
  String name,
);

/// How the system bus is opened. Only [canReachBlueZOn] uses it, and only a
/// test passes it.
typedef OpenSystemBus = DBusClient Function();

/// The three answers the bus can give, against an arbitrary call so that each
/// is reachable from a test.
///
/// The real bus is a property of the host: no test can arrange for it to be
/// absent, and none can arrange for the state that matters here - a bus that
/// answers, and will not produce [_bluezBusName].
///
/// [window] is the second thing only a test passes, for the same reason as
/// [hasAdapterIn]'s `list`: the arm it reaches is the one that turns this
/// guard off, so it is the last one that should go untested, and waiting out
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
    // for a machine that has it.
    //
    // The arm this can only be entered from is the `.timeout` above:
    // `package:dbus` never throws `dart:async`'s [TimeoutException] - its own
    // timeout is an error *reply*, `DBusTimeoutException`, which is a
    // `DBusErrorException` and lands below. So the sentence printed here is
    // always true of what happened.
    //
    // What fails open is less comfortable than the kernel read's sibling, and
    // worth saying rather than glossing: there, an unreadable /sys is
    // uncorrelated with BlueZ working, so handing over is a fair bet. Here,
    // handing over addresses the same unresponsive bus this probe just timed
    // out on. The bet is that the fault this exists for arrives as an error
    // reply and not as silence - which is what both reported hosts did, and
    // not a law: a confined bus proxy with no `--talk=org.bluez` rule can
    // stall instead of refusing, on exactly the class of host where BlueZ is
    // also unreachable. Failing closed on a momentarily busy bus is the worse
    // trade, so the bet stands and the breadcrumb below is what makes it
    // visible when it loses - it is emitted moments before the call that
    // crashes, so it arrives on that very event.
    Log.warnOnce(
      'linux/bluez-silent',
      '[FlipperClient] Linux: the system bus did not say whether '
          '$_bluezBusName can start within ${window.inMilliseconds}ms; asking '
          'the plugin anyway',
    );
    return true;
  } catch (e) {
    // Every other failure is a no, and deliberately not classified. The useful
    // property is not the error's name: it is that this call and the backend's
    // first call address the same name on the same bus, so a bus that will not
    // produce [_bluezBusName] for us will not produce it for the backend
    // either. Needles would narrow a general answer to the hosts we happen to
    // have heard from, and ADR 0008 asks for classification where a caller
    // acts on the kind - nothing here does.
    //
    // Catches [Object] and not [Exception], which is load-bearing twice over.
    // A throw escaping this function rejects `availabilityState`, and on the
    // first call that is the orphan this file exists to prevent - and a
    // non-`Exception` throw is reachable from the real call, not just from a
    // test: `DBusClient.startServiceByName` throws a bare `String` on a return
    // code it does not recognise.
    //
    // "treating BLE as unavailable" and not "BLE is unavailable on this
    // machine": for an `AccessDenied` from a bus policy, an SELinux denial or a
    // confined proxy, the second is a claim about the host and is false. This
    // reports what was decided and leaves the bus's own words to say why.
    // Keyed on the bus's own words, capped at two. A single latch keeps
    // whichever cause arrived first, so an early-boot `SocketException` from a
    // socket that is not up yet would be the only line this process ever
    // recorded and the `unknown unit` that is the actual diagnosis would be
    // suppressed behind it. Uncapped it is unbounded over distinct errors,
    // which is the Sentry burst shape; two is already more than any reported
    // host produced.
    Log.warnOnce(
      'linux/bluez-refused',
      '[FlipperClient] Linux: $_bluezBusName will not start on the system '
          'bus ($e); treating BLE as unavailable on this machine',
      cause: '$e',
      causes: 2,
    );
    return false;
  }
}

/// Lets go of [close]'s bus, bounded, and never throws.
///
/// Split out and `@visibleForTesting` because both of its answers matter and
/// neither is reachable through a real [DBusClient]: see [_bluezCloseWindow]
/// for what an unbounded close does, and note that the `catch` cannot see it,
/// because a hang is not a throw.
///
/// A timeout here leaks the socket and three subscriptions, which is the right
/// way round - it only happens on a bus that has stopped answering, where BLE
/// is already gone, and leaking an fd beats never answering. It is `warn` and
/// not `debug` because the leak is one per availability read and `debug` is
/// compiled out of a release build, so nothing would record it where it
/// happens.
///
/// Two arms, because one `catch` printed the leak sentence for a close that
/// threw instantly and both halves of it were then false.
@visibleForTesting
Future<void> closeBusQuietly(
  Future<void> Function() close, {
  Duration window = _bluezCloseWindow,
}) async {
  try {
    await close().timeout(window);
  } on TimeoutException {
    Log.warnOnce(
      'linux/bus-close-stuck',
      '[FlipperClient] Linux: letting go of the system bus did not finish '
          'within ${window.inMilliseconds}ms; its socket is leaked',
    );
  } catch (e) {
    // Nothing leaked and nothing waiting: the close itself refused, the answer
    // above is already decided, and a throw out of a `finally` would replace
    // it with the uncatchable kind this file exists to avoid.
    Log.warnOnce(
      'linux/bus-close-failed',
      '[FlipperClient] Linux: letting go of the system bus failed ($e)',
    );
  }
}

/// [canReachBlueZVia] on a client this function owns and closes.
///
/// A client per call, and the cost is worth stating plainly because the
/// comments here are the argument for the design: a fresh [DBusClient] is a
/// socket connect, a SASL `EXTERNAL` handshake, `Hello`, then a
/// `GetNameOwner` and an `AddMatch` for each of the three name-ownership
/// streams `_connect` subscribes, then the one call this is for, then three
/// `RemoveMatch` replies on the way out. Ten round trips, not one. On a local
/// Unix socket that is sub-millisecond and off the UI thread, and
/// `hasAdapter()` - a `stat` - short-circuits it on the machines that would
/// pay for nothing. It is not cached: the answer can change under the app
/// when someone installs `bluez`, and caching the negative would hold BLE
/// off for the life of the process.
///
/// Its own client rather than the plugin's, which is the whole point: this
/// future is ours, so its rejection has a listener and is catchable, where the
/// backend's `_initializationCompleter` rejection has neither.
@visibleForTesting
Future<bool> canReachBlueZOn(OpenSystemBus open) async {
  DBusClient? bus;
  try {
    return await canReachBlueZVia((name) {
      // Opened in here, inside [canReachBlueZVia]'s own `try`, and that
      // placement is the point rather than a style: `DBusClient.system()`
      // reads `DBUS_SYSTEM_BUS_ADDRESS` and hands it to `DBusAddress`, which
      // throws `FormatException` *synchronously* for an address with no
      // transport prefix - the bare `/run/dbus/system_bus_socket` form people
      // write in units and containers. Hoisted above the `try` it was the one
      // statement in this file nothing caught, in the one function whose
      // contract is that it always answers. It rejected `availabilityState`,
      // which `readAccess` reports and answers `unknown` for, which is treated
      // as usable, which scans - and `startScan` is then the first touch of the
      // backend. The same orphan, the same fatal report, through a door one
      // line wide.
      final opened = bus = open();
      return opened.startServiceByName(name);
    });
  } finally {
    final opened = bus;
    // Nothing to close when the open itself threw, and `bus` is still null.
    if (opened != null) await closeBusQuietly(opened.close);
  }
}

/// The default [CanReachBlueZ]: what the system bus says about BlueZ.
///
/// `StartServiceByName` and not `NameHasOwner` or `ListActivatableNames`.
/// `NameHasOwner` reports current registration and never activates, so on a
/// healthy host with `bluetoothd` merely stopped it answers false while the
/// plugin would have worked - it rejects machines that are fine.
/// `ListActivatableNames` depends on a reading of the reported error:
/// `NameHasNoOwner: ... activation request failed: unknown unit` *reads* as
/// the bus finding an activation entry that systemd cannot honour, since a
/// genuinely missing `.service` file answers `ServiceUnknown` instead - and if
/// that reading is right, the name is in `ListActivatableNames` on the broken
/// host too. The reading is not verified and does not need to be: asking the
/// bus to actually produce the name answers no in either world, which is why
/// it is the question asked. Where the daemon is already up it answers
/// `alreadyRunning` without starting anything.
///
/// A tear-off of [canReachBlueZOn] rather than a body, so that there is no
/// second copy of the open-inside-the-guard placement to get wrong, and so
/// that the production wiring is one identity a test can assert.
Future<bool> dbusCanReachBlueZ() => canReachBlueZOn(DBusClient.system);

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
  /// QUNLEASHED-C, and this method's own comment named the hole for the whole
  /// of 0.17.1 before [canReachBlueZ] closed it (#443).
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
  /// (Today they cannot - `plugin_reach_guard_test.dart` pins those two, and
  /// the `availabilityStream` subscription, below an availability read in the
  /// method that makes them. It pins nothing about *when* the rest run, so a
  /// guard on position is a weaker thing to rest on than a gate that
  /// answers.)
  ///
  /// **And no handler is a substitute for either, which the comment this
  /// replaces had wrong twice.** It named the app's
  /// `PlatformDispatcher.onError` as the general containment. That slot cannot
  /// classify anything: `sentry_flutter`'s `OnErrorIntegration` installs over
  /// the app's handler, and after delegating to it captures at
  /// `SentryLevel.fatal` unconditionally - the handler's return value sets
  /// `Mechanism.handled` and nothing else. The lever that exists is
  /// `beforeSend`, already installed in the app's `telemetry/options.dart`,
  /// where returning null drops an event.
  ///
  /// More to the point, dropping the report would leave the user worse off.
  /// The backend's catch calls `completeError` and never nulls
  /// `_initializationCompleter`, so one failed touch poisons it for the life
  /// of the process: `_ensureInitialized` then awaits that same rejected
  /// future forever, and BLE stays dead even after the user installs `bluez`.
  /// Only not calling keeps the one initialisation attempt unspent. A gate
  /// buys a working radio; a handler buys a quieter crash report.
  ///
  /// **Two, and not the first two of a growing list.** `_ensureInitialized`
  /// has exactly two external dependencies - `_client.connect()`, which needs
  /// the bus and the name, and `_waitForAdapter`, which needs an adapter - and
  /// there is one gate per dependency. What a reader might imagine as a third
  /// is already answered: rfkill and a switched-off radio come back from the
  /// plugin as `poweredOff`, and a denying bus policy or a stopped daemon land
  /// in the probe's own `catch`.
  ///
  /// What is left after both gates is a bus that produced `org.bluez` and a
  /// backend that failed anyway - `_waitForAdapter` polls ten times at 100 ms
  /// and throws `Bluetooth adapter unavailable` down the identical path. That
  /// residue is `beforeSend`'s, and these gates stand whether or not it ever
  /// changes: they answer locally, and on a machine that will never have a
  /// radio they also skip that poll and `FlipperClient.bleAvailabilityWait`.
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
      // `warn` and not `info`, and this is not a style choice: the app pins
      // this library's level at `LogService._keptFrom`, which is `warning`, so
      // an `info` is dropped outright in a release build without a breadcrumb
      // reader and is a breadcrumb at best with one. Before this method existed
      // the same condition reached `readAccess`'s catch and was reported at
      // `error`. Downgrading it to `info` would have traded a crash for no
      // record at all - and this line is the whole explanation for a BLE
      // surface that finds nothing, which is the failure mode #351 is about.
      //
      // Once per isolate: this is a property of the machine, not of the call,
      // and `availabilityState` runs per scan, per connect and on every resume
      // re-read.
      Log.warnOnce(
        'linux/no-controller',
        '[FlipperClient] Linux: no Bluetooth controller in '
            '$_sysClassBluetooth; BLE is unavailable on this machine',
      );
      return uble.AvailabilityState.unsupported;
    }
    // Awaited before the delegation and not beside it: the point is that
    // nothing touches the backend until the bus has agreed it can produce
    // `org.bluez`. The line that says why is in [canReachBlueZVia], which is
    // where the bus's own words are.
    //
    // Asked again on every call until it says yes once; see [_bluezReached]
    // for why only the yes is remembered.
    if (!_bluezReached) {
      if (!await canReachBlueZ()) return uble.AvailabilityState.unsupported;
      _bluezReached = true;
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
  _bluezReached = false;
  Log.debugResetNotices();
}

class LinuxBleTransport extends UniversalBleTransportBase {
  LinuxBleTransport._(BleDiscoveredDevice device)
    : super(device, UniversalBleOps());

  // BlueZ reads the MTU off the resolved characteristics, so there is nothing
  // to ask before discovery - through universal_ble 2.x asking anyway failed
  // with `operationNotSupported`, which is why this link had no MTU reading at
  // all, and from 3.0.0 asking triggers a discovery to answer. Either way the
  // read belongs after discovery, which is what this says.
  @override
  bool get mtuSettlesAfterDiscovery => true;

  static Future<LinuxBleTransport> create(BleDiscoveredDevice device) async {
    final transport = LinuxBleTransport._(device);
    await transport.configure();
    return transport;
  }
}
