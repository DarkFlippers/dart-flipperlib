// That a Linux machine with no Bluetooth controller is answered here, and the
// plugin is never asked.
//
// Not a preference. universal_ble's bluez backend initialises on its first
// call, and `_ensureInitialized` (universal_ble_linux.dart) does this when it
// fails:
//
//     _initializationCompleter?.completeError(e);
//     await _client.close();
//     rethrow;
//
// The `rethrow` is the part a call site can catch, and flipperlib did catch
// it - `readAccess` logged it at `error` and answered `unknown`. The
// `completeError` is the part it cannot: nothing is awaiting that completer at
// the moment it rejects. A later caller does await it - the catch never clears
// the field, so every call after the first awaits an already-rejected future
// and is handled - but the first rejection has no listener, and a rejected
// future with no listener goes to the root zone, which in this app is
// `PlatformDispatcher.onError`, which is a fatal crash report. The user's app
// had already started; what they saw was it die.
//
// There are two hosts, not one, and the first fix only covered the first:
//
//   - QUNLEASHED-Q, Debian on 0.17.0: no radio, so the kernel read answers it
//     and the plugin is never asked.
//   - QUNLEASHED-C, Arch, first seen on 0.17.0 and regressed on 0.17.1 -
//     which matters, because only the 0.17.1 events ran behind the kernel
//     read. The event names commit `97f217e0`, whose flipperlib is `9db78a9`,
//     which contains it. So sysfs answered *yes* on that host and it
//     delegated anyway, and what it answered yes about is either a controller
//     it listed or a /sys this process could not read - `hasAdapterIn` fails
//     open on the second, and the `cannot read` breadcrumb is what separates
//     them. Neither #443 nor anything here cites that breadcrumb, so the
//     distinction is open; the gate below does not depend on which it was.
//     Its error was "Could not activate remote peer 'org.bluez': activation
//     request failed: unknown unit", and `hciN` is created by the kernel
//     while `org.bluez` comes from a package - so a listed controller is no
//     evidence of BlueZ. That is #443, deterministic on that host: it fired
//     during `ui.load`, before the user had done anything.
//
// and a third is reachable without either: `_waitForAdapter` polls ten times
// at 100ms and throws `Bluetooth adapter unavailable` down the identical path.
// That one is not closed here and cannot be from a call site - see
// `LinuxBlePlatform.availabilityState` for whose job it is.
//
// So the only fix available to a caller is to not make the call, and it takes
// two questions to know not to: whether the kernel lists a controller, and
// whether the bus will produce `org.bluez`. These tests pin both - each
// short-circuit answers, and the plugin call is not reached.
import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flipperlib/src/common/log.dart';
import 'package:flipperlib/src/transport/ble/linux.dart';
import 'package:flipperlib/src/transport/ble/platform.dart';
import 'package:flipperlib/src/transport/ble/unsupported.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart' as uble;

/// The real [LinuxBlePlatform] with the kernel read answered and the plugin
/// call counted.
///
/// Overriding `askPluginForAvailability()` rather than `availabilityState()` is
/// the point: the body under test - the short-circuit and the delegation - is
/// the production one. That is also why the base class has the method at all.
class _CountedLinux extends LinuxBlePlatform {
  /// [bluezReachable] defaults to true so that every case written before the
  /// bus gate existed still exercises the path it was written for. The
  /// opposite default would have let the delegation cases below pass with the
  /// plugin unreached - the same trap `plugin` not defaulting to `unsupported`
  /// avoids one layer up. [canReachBlueZ] overrides it for the one case that
  /// needs to see *whether* the question was asked rather than answer it.
  /// [hasAdapter] overrides [adapterPresent] for the one case that needs the
  /// real `hasAdapterIn` rather than a stubbed answer, so that the fail-open
  /// arm is actually driven rather than described.
  _CountedLinux({
    required bool adapterPresent,
    bool bluezReachable = true,
    CanReachBlueZ? canReachBlueZ,
    HasBluetoothAdapter? hasAdapter,
    this.plugin = uble.AvailabilityState.poweredOn,
  }) : super(
         hasAdapter: hasAdapter ?? (() => adapterPresent),
         canReachBlueZ: canReachBlueZ ?? (() async => bluezReachable),
       );

  /// Not `unsupported`, deliberately: with that as the default, the case
  /// asserting the short-circuit's answer would hold whether it fired or not.
  final uble.AvailabilityState plugin;

  int pluginReads = 0;

  @override
  Future<uble.AvailabilityState> askPluginForAvailability() async {
    pluginReads++;
    return plugin;
  }
}

/// QUNLEASHED-C's own refusal, raised where this code can catch it.
///
/// Hoisted because the error name was written out at six sites and the
/// `refuse()` closure at two of them verbatim - so changing what the probe
/// asks the bus, which `dbusCanReachBlueZ`'s doc argues about at length, was
/// six edits with nothing failing if one were missed.
Future<bool> _refusesBlueZ() => canReachBlueZVia(
  (_) async => throw DBusErrorException(
    DBusMethodErrorResponse('org.freedesktop.DBus.Error.NameHasNoOwner'),
  ),
);

/// A host with no system bus at all: the client throws instead of replying.
Future<bool> _hasNoBus([String cause = 'no system bus socket']) =>
    canReachBlueZVia((_) async => throw SocketException(cause));

/// A bus whose socket is open and which has stopped answering.
///
/// `Duration.zero` rather than waiting out `_bluezStartWindow`: the arm is the
/// one that turns the guard off, so it is the last that should go untested,
/// and two seconds in the suite to reach it is not a price worth paying.
Future<bool> _busGoesQuiet() => canReachBlueZVia(
  (_) => Completer<DBusStartServiceByNameReply>().future,
  window: Duration.zero,
);

void main() {
  setUp(debugResetLinuxBleNotices);

  group('a Linux machine with no Bluetooth controller', () {
    test('is answered unsupported', () async {
      final platform = _CountedLinux(adapterPresent: false);

      expect(
        await platform.availabilityState(),
        uble.AvailabilityState.unsupported,
      );
    });

    test('does not reach the plugin', () async {
      final platform = _CountedLinux(adapterPresent: false);

      await platform.availabilityState();

      // The assertion the fix exists for. An answer of `unsupported` with the
      // call still made would be the same crash with better wording: the
      // rejection that kills the app is raised inside the call, not returned
      // from it.
      expect(platform.pluginReads, 0);
    });

    test('readAccess goes through the platform, not straight to the plugin', () async {
      final platform = _CountedLinux(adapterPresent: false);

      // The mapping itself is already pinned in `ble_access_test.dart`. What
      // this case uniquely holds is the wiring: `readAccess` calls the
      // *virtual* `availabilityState()`, so the Linux short-circuit applies to
      // the startup permission read too. Tighten that line to call
      // `askPluginForAvailability()` directly and the short-circuit is
      // bypassed on the path QUNLEASHED-Q actually came in on, and this is the
      // only case anywhere that notices.
      expect(await platform.readAccess(), BleAccess.unsupported);
      expect(platform.pluginReads, 0);
    });
  });

  group('a Linux machine with a controller and no BlueZ', () {
    test('is answered unsupported', () async {
      final platform = _CountedLinux(
        adapterPresent: true,
        bluezReachable: false,
      );

      expect(
        await platform.availabilityState(),
        uble.AvailabilityState.unsupported,
      );
    });

    test('does not reach the plugin', () async {
      final platform = _CountedLinux(
        adapterPresent: true,
        bluezReachable: false,
      );

      await platform.availabilityState();

      // The assertion the second gate exists for, and the one that fails
      // against every build before it: with the kernel read alone this host
      // delegated, and the rejection raised inside that call is what was
      // reported as a fatal crash.
      expect(platform.pluginReads, 0);
    });

    test('readAccess goes through the same gate', () async {
      // The startup permission read, which is the path QUNLEASHED-C came in
      // on: `in_foreground: false`, `op: ui.load`, before the user had done
      // anything. `readAccess` calls the *virtual* `availabilityState()`, so
      // both gates apply to it; tighten that line to call
      // `askPluginForAvailability()` and this is what notices.
      final platform = _CountedLinux(
        adapterPresent: true,
        bluezReachable: false,
      );

      expect(await platform.readAccess(), BleAccess.unsupported);
      expect(platform.pluginReads, 0);
    });

    test('and is reached through the real fail-open arm too', () async {
      // `hasAdapterIn` answers true for a /sys it cannot read, so a confined
      // host reaches the bus probe on that answer rather than on a listed
      // controller - and which of the two QUNLEASHED-C's host was is not
      // established, so the gate must not care.
      //
      // The first version of this case passed `adapterPresent: true` and was a
      // verbatim duplicate of the two above: `hasAdapter` was a stub, so no
      // /sys read happened at all and the name promised coverage the body did
      // not create. That is the anti-pattern CLAUDE.md names, so this one
      // drives the real `hasAdapterIn` fail-open arm instead.
      final tmp = Directory.systemTemp.createTempSync('sysfs_masked_test');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final platform = _CountedLinux(
        adapterPresent: true,
        bluezReachable: false,
        hasAdapter: () => hasAdapterIn(
          tmp,
          list: (_) => throw const FileSystemException('/sys is masked'),
        ),
      );

      expect(
        await platform.availabilityState(),
        uble.AvailabilityState.unsupported,
      );
      expect(platform.pluginReads, 0);
    });
  });

  group('the bus is asked only until it says yes', () {
    test('a yes is remembered, so later reads do not re-ask', () async {
      // The probe is a socket, an auth handshake and ten round trips, and it
      // runs per scan, per connect and on every resume - which on desktop
      // Flutter means on window focus. After one yes it can buy nothing: the
      // backend has set `isInitialized`, so every later availability read is
      // an in-memory field read that cannot orphan anything.
      var asked = 0;
      final platform = _CountedLinux(
        adapterPresent: true,
        canReachBlueZ: () async {
          asked++;
          return true;
        },
      );

      await platform.availabilityState();
      await platform.availabilityState();
      await platform.availabilityState();

      expect(asked, 1);
      expect(platform.pluginReads, 3);
    });

    test('a no is not remembered, so installing bluez is noticed', () async {
      // The half that must *not* be cached, and the reason the asymmetry is
      // deliberate rather than lazy: because the gate refuses before the
      // plugin is touched, the backend's one initialisation attempt is still
      // unspent, so a host where `bluez` appears mid-session gets working BLE
      // on the next scan. Caching the refusal would hold it off until relaunch.
      //
      // `asked` and not just the answers: setting the flag *above* the check
      // caches the no as well, and the two availability answers below are
      // identical either way - the second call would delegate because the flag
      // was set, not because the bus was asked again. That mutant survived a
      // version of this case that only looked at the answers.
      var asked = 0;
      var reachable = false;
      final platform = _CountedLinux(
        adapterPresent: true,
        canReachBlueZ: () async {
          asked++;
          return reachable;
        },
      );

      expect(
        await platform.availabilityState(),
        uble.AvailabilityState.unsupported,
      );
      expect(asked, 1);
      expect(platform.pluginReads, 0);

      reachable = true;

      expect(
        await platform.availabilityState(),
        uble.AvailabilityState.poweredOn,
      );
      expect(asked, 2);
      expect(platform.pluginReads, 1);
    });
  });

  group('the order the two gates run in', () {
    test('the bus is not asked when the kernel already said no', () async {
      // Order, and worth pinning: the kernel read is a `stat`, the bus read is
      // a socket, an auth handshake and a round trip. A machine with no radio
      // should pay for neither, and swapping the two `if`s is how it would
      // come to - with every other case in this file still green.
      var asked = false;
      final platform = _CountedLinux(
        adapterPresent: false,
        canReachBlueZ: () async {
          asked = true;
          return true;
        },
      );

      expect(
        await platform.availabilityState(),
        uble.AvailabilityState.unsupported,
      );
      expect(asked, isFalse);
      expect(platform.pluginReads, 0);
    });
  });

  group('a Linux machine that has one', () {
    test('asks the plugin and passes its answer through', () async {
      // Both gates open: a controller in sysfs and a bus that will produce
      // `org.bluez`. That is every Linux machine BLE works on, and this is the
      // case that fails if either gate starts answering on its own.
      final platform = _CountedLinux(
        adapterPresent: true,
        plugin: uble.AvailabilityState.poweredOff,
      );

      expect(
        await platform.availabilityState(),
        uble.AvailabilityState.poweredOff,
      );
      // Pins that the short-circuit above is what produced `unsupported`,
      // rather than this method having stopped asking anything at all.
      expect(platform.pluginReads, 1);
    });

    test('is not special-cased when the plugin says unsupported', () async {
      // The plugin's own `unsupported` and ours are the same answer and must
      // stay indistinguishable to callers; this is here so that reading one
      // test in isolation does not suggest otherwise.
      final platform = _CountedLinux(
        adapterPresent: true,
        plugin: uble.AvailabilityState.unsupported,
      );

      expect(
        await platform.availabilityState(),
        uble.AvailabilityState.unsupported,
      );
      expect(platform.pluginReads, 1);
    });
  });

  group('the kernel read', () {
    // Against a directory rather than the real path, because the real one is a
    // property of the host: absent on Windows, absent or empty on a CI runner,
    // populated on a laptop. Asserting the value there would be asserting the
    // machine. These three are the branches that decide whether the fix above
    // ever fires, and none of them was reachable before this group existed.
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('sysfs_bt_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('says no when the directory is absent', () {
      final gone = Directory('${tmp.path}/never-made');

      // The common case, and the kernel's way of saying the `bluetooth`
      // module was never loaded.
      expect(hasAdapterIn(gone), isFalse);
    });

    test('says no when it is there and empty', () {
      // The module loaded and no controller turned up: a dongle unplugged, a
      // VM with the device removed.
      expect(hasAdapterIn(tmp), isFalse);
    });

    test('says yes for one entry', () {
      Directory('${tmp.path}/hci0').createSync();

      expect(hasAdapterIn(tmp), isTrue);
    });

    test('answers yes anyway when it cannot read the directory', () {
      // The arm that turns the guard off, and the only one that hands control
      // to the call this whole file exists to avoid. It answers `true` on
      // purpose: the two wrong answers are not equal, and switching Bluetooth
      // off for a machine that has a radio is the worse one. A /sys masked by
      // a Flatpak or Snap confinement is the real case.
      expect(
        hasAdapterIn(
          tmp,
          list: (_) => throw const FileSystemException('/sys is masked'),
        ),
        isTrue,
      );
    });

    test('never throws against the real path, whatever the host', () {
      // Its whole job, and asserted on the function rather than through a
      // platform instance because the function is what is being claimed about.
      // A throw out of here does not crash the app - `availabilityState` is
      // `async`, so it rejects, and `readAccess` catches that and answers
      // `unknown` - but it does disable BLE on a machine that may have a
      // radio, which is the one wrong answer this read must not give.
      expect(sysfsHasAdapter, returnsNormally);
    });
  });

  group('the wiring production actually gets', () {
    // The gap this closes is the one that matters most and reads like an
    // implementation detail. `ble.dart` builds `const LinuxBlePlatform()` with
    // no arguments, so the constructor defaults *are* the production wiring -
    // and every case in this file injects both seams, so nothing else here
    // evaluates them. Replace either default with a stub that answers `true`
    // and the gate is textually present, in order, above the delegation, and
    // wired to nothing: #443 reopened with all 284 cases green, including the
    // source guard. Verified by doing it.
    //
    // An identity assertion and not a behavioural one, because the behavioural
    // version would assert the machine: on a Linux laptop with bluez installed
    // the real pair answers `poweredOn`, on a Windows runner `unsupported`.
    test('is the kernel read and the bus probe, not a stand-in', () {
      const platform = LinuxBlePlatform();

      expect(platform.hasAdapter, same(sysfsHasAdapter));
      expect(platform.canReachBlueZ, same(dbusCanReachBlueZ));
    });
  });

  group('the bus read', () {
    // Against a passed-in bus call rather than the real bus, for the reason
    // the kernel group gives about the real path: the host either has a system
    // bus or does not, and no test can give it one that finds an activation
    // entry it cannot honour - which is the only state that matters here.
    //
    // `startServiceByName` is what the production code calls, so these stand
    // in for its three outcomes and nothing else.
    test('says yes when the service starts', () async {
      expect(
        await canReachBlueZVia(
          (_) async => DBusStartServiceByNameReply.success,
        ),
        isTrue,
      );
    });

    test('says yes when it was already running', () async {
      // The common case on a working machine, and not a different answer:
      // which process started the daemon is not a question this asks.
      expect(
        await canReachBlueZVia(
          (_) async => DBusStartServiceByNameReply.alreadyRunning,
        ),
        isTrue,
      );
    });

    test('asks for org.bluez and nothing else', () async {
      // The design's load-bearing claim is that this call and the backend's
      // first call address the same name on the same bus. Every other fake
      // here discards its argument, and the assertion on the warn text reads
      // the interpolated constant rather than what was passed - so with the
      // name alone unpinned, `start('org.bluez.obex')` kept this file green.
      // Verified.
      String? asked;

      expect(
        await canReachBlueZVia((name) async {
          asked = name;
          return DBusStartServiceByNameReply.success;
        }),
        isTrue,
      );
      expect(asked, 'org.bluez');
    });

    test('says no when the bus refuses to start it', () async {
      // QUNLEASHED-C's own error, raised where this code can catch it. The
      // same throw from inside universal_ble's backend is the one that cannot
      // be caught, which is the whole reason this call is made from here.
      expect(
        await canReachBlueZVia(
          (_) async => throw DBusErrorException(
            DBusMethodErrorResponse(
              'org.freedesktop.DBus.Error.NameHasNoOwner',
              [
                const DBusString(
                  "Could not activate remote peer 'org.bluez': activation "
                  'request failed: unknown unit',
                ),
              ],
            ),
          ),
        ),
        isFalse,
      );
    });

    test('says no when there is no bus to ask', () async {
      // A host with no D-Bus at all: the client throws on connect rather than
      // replying. Not a `DBusErrorException`, which is why the arm catches
      // every throw and classifies none of them.
      expect(await _hasNoBus(), isFalse);
    });

    test(
      'says no when the throw is an Error rather than an Exception',
      () async {
        // The arm catches `Object`, and that is load-bearing rather than lax: a
        // throw escaping this function rejects `availabilityState`, and on the
        // first call that rejection is the orphan this whole file exists to
        // prevent. An `on Exception` arm would let this one through.
        expect(
          await canReachBlueZVia((_) async => throw StateError('closed')),
          isFalse,
        );
      },
    );

    test('answers yes when the bus does not answer', () async {
      // The arm that turns this guard off, and like the kernel read's it fails
      // open on purpose: no answer is not an answer, and switching Bluetooth
      // off for a machine that has it is the worse of the two wrong answers.
      // The fault this probe exists for arrives as an error reply in under a
      // millisecond, never as silence.
      expect(await _busGoesQuiet(), isTrue);
    });

    test('a bus that cannot be opened is a no, not a throw', () async {
      // `DBusClient.system()` is not inert: it reads `DBUS_SYSTEM_BUS_ADDRESS`
      // and `DBusAddress` throws `FormatException` synchronously for an
      // address with no transport prefix - the bare
      // `/run/dbus/system_bus_socket` form people write in units and
      // containers. That open used to sit above the `try`, where nothing
      // caught it: it rejected `availabilityState`, `readAccess` answered
      // `unknown`, the picker scanned, and `startScan` became the first touch
      // of the backend. The same crash through a one-line door.
      expect(
        await canReachBlueZOn(
          () => throw const FormatException('no transport in address'),
        ),
        isFalse,
      );
    });

    test('lets go of the bus, and a close that will not finish is bounded', () async {
      // The arm with no reachable alternative. `DBusClient.close()` cancels the
      // three signal subscriptions `_connect` installed, each cancel awaits a
      // `RemoveMatch` *method call*, and `package:dbus` never times out a
      // reply - so on a bus that has stopped answering, an unbounded close
      // never returns and `availabilityState` never completes. The `catch`
      // cannot see that: a hang is not a throw. It strands the client's
      // request chain and the app's permission read, which is worse than
      // either answer the gate was choosing between.
      final completer = Completer<void>();

      await expectLater(
        closeBusQuietly(() => completer.future, window: Duration.zero),
        completes,
      );
    });

    test('a stuck close says the socket leaked, and a failed one does not', () async {
      // One `catch` served both arms and printed the leak sentence for a close
      // that threw instantly, where both halves of it were false. Nothing
      // observed `_saidCloseStuck` at all before this case.
      final said = <String>[];
      final previous = Log.sink;
      Log.sink = (level, message) => said.add(message);
      addTearDown(() => Log.sink = previous);

      await closeBusQuietly(
        () => Completer<void>().future,
        window: Duration.zero,
      );
      await closeBusQuietly(() async => throw StateError('socket gone'));

      expect(said.where((m) => m.contains('socket is leaked')), hasLength(1));
      expect(
        said.where((m) => m.contains('letting go of the system bus failed')),
        hasLength(1),
      );
    });

    test('a close that throws is swallowed, not propagated', () async {
      // The answer is already decided by the time the `finally` runs, and a
      // throw out of a `finally` would replace it with the uncatchable kind
      // this file exists to avoid.
      await expectLater(
        closeBusQuietly(() async => throw StateError('socket gone')),
        completes,
      );
    });

    test('never throws against the real bus, whatever the host', () async {
      // Its whole job. The answer is the host's - a Linux runner with a bus
      // may say either, Windows and macOS have no socket to connect to and
      // fail in about ten milliseconds - so this asserts only that it
      // resolves, which is the property the caller depends on. A throw out of
      // here rejects `availabilityState`, and on the first call that is the
      // uncatchable kind.
      //
      // It has a side effect worth knowing about before running the suite on
      // a Linux desktop: where bluez *is* installed, `StartServiceByName`
      // genuinely starts `bluetoothd`. Harmless, and not something the other
      // cases do - they all go through a fake.
      await expectLater(dbusCanReachBlueZ(), completes);
    });
  });

  group('the notice about a machine with no radio', () {
    // Without these, `debugResetLinuxBleNotices` is a `@visibleForTesting`
    // export whose effect nothing observes, and the latch itself is untested.
    // `availabilityState` runs per scan, per connect and on every resume
    // re-read, and these lines are `warn`, which this app keeps in release -
    // so an unlatched one is Sentry volume, not just noise.
    late List<String> said;
    late FlipperLogSink? previous;

    setUp(() {
      said = [];
      previous = Log.sink;
      Log.sink = (level, message) => said.add(message);
    });
    tearDown(() => Log.sink = previous);

    test('is said once, not once per call', () async {
      final platform = _CountedLinux(adapterPresent: false);

      await platform.availabilityState();
      await platform.availabilityState();
      await platform.availabilityState();

      expect(
        said.where((m) => m.contains('no Bluetooth controller')),
        hasLength(1),
      );
    });

    test(
      'is said again after a reset, so the latch is what is holding it',
      () async {
        // Otherwise the case above would also pass if the line were emitted
        // never, or once ever and never again in this isolate.
        final platform = _CountedLinux(adapterPresent: false);

        await platform.availabilityState();
        debugResetLinuxBleNotices();
        await platform.availabilityState();

        expect(
          said.where((m) => m.contains('no Bluetooth controller')),
          hasLength(2),
        );
      },
    );

    test(
      'says why it could not read, once, when /sys will not answer',
      () async {
        // The fail-open arm's own line. Same latch, separate flag: these are
        // different facts about different reads. This one and the
        // no-*controller* line are mutually exclusive per isolate - a masked
        // /sys fails open, so `hasAdapter()` is true forever and that branch
        // is never entered - but this one and the no-*BlueZ* line are not,
        // which the case below holds. A shared flag would make either line's
        // absence depend on the other's history, including across the cases in
        // this group.
        expect(
          hasAdapterIn(
            Directory.systemTemp,
            list: (_) => throw const FileSystemException('/sys is masked'),
          ),
          isTrue,
        );
        expect(
          hasAdapterIn(
            Directory.systemTemp,
            list: (_) => throw const FileSystemException('/sys is masked'),
          ),
          isTrue,
        );

        expect(said.where((m) => m.contains('cannot read')), hasLength(1));
      },
    );

    test('says BlueZ will not start, once, and names the bus error', () async {
      // Latched like its siblings and for the same reason - this runs per
      // scan, per connect and on every resume re-read, and it is `warn`, which
      // the app keeps in release. The error text is asserted because it is the
      // whole diagnosis: without it the line says a machine has no Bluetooth
      // and not that installing `bluez` would fix it.
      expect(await _refusesBlueZ(), isFalse);
      expect(await _refusesBlueZ(), isFalse);

      final lines = said.where((m) => m.contains('will not start')).toList();
      expect(lines, hasLength(1));
      expect(lines.single, contains('NameHasNoOwner'));
      expect(lines.single, contains('org.bluez'));
    });

    test('says the bus went quiet, once', () async {
      expect(await _busGoesQuiet(), isTrue);
      expect(await _busGoesQuiet(), isTrue);

      expect(
        said.where((m) => m.contains('did not say whether')),
        hasLength(1),
      );
    });

    test('a confined host that also has no BlueZ says both lines', () async {
      // The pair that is *not* mutually exclusive, and the one merging them
      // actually costs something: a masked /sys fails open, so this host
      // reaches the bus probe, and both facts are true at once. With one
      // shared flag whichever fired first suppresses the other - and the
      // suppressed one may be the masked-/sys breadcrumb that tells "the fix
      // did not work" from "the fix could not see /sys".
      //
      // The refusal topic's two causes are spent first, on purpose. Saying one
      // of each and asserting one of each is not enough: with the two topics
      // merged, the refusal's cap of two leaves room for the sysfs line to be
      // said anyway, so that ordering passes while sharing a latch. Exhausting
      // the cap first makes the two topics' independence the only thing that
      // can produce the third line. That mutant survived the weaker version.
      expect(await _hasNoBus('first cause'), isFalse);
      expect(await _hasNoBus('second cause'), isFalse);

      expect(
        hasAdapterIn(
          Directory.systemTemp,
          list: (_) => throw const FileSystemException('/sys is masked'),
        ),
        isTrue,
      );

      expect(said.where((m) => m.contains('will not start')), hasLength(2));
      expect(said.where((m) => m.contains('cannot read')), hasLength(1));
    });

    test(
      'says a second, different cause rather than latching the first',
      () async {
        // A bool latch keeps whichever error arrived first, so an early-boot
        // `SocketException` from a bus socket that is not up yet would be the
        // only line this process ever recorded and the `unknown unit` that is
        // the actual diagnosis would be suppressed behind it.
        //
        // The repeat at the end is the half that matters as much: a single
        // slot keyed on the last message - which is what I wrote first - says
        // something on *every* call for a host that alternates, which is the
        // burst this latch exists to avoid. This case failed against that
        // version, with three lines.
        expect(await _hasNoBus(), isFalse);
        expect(await _refusesBlueZ(), isFalse);
        expect(await _hasNoBus(), isFalse);

        final lines = said.where((m) => m.contains('will not start')).toList();
        expect(lines, hasLength(2));
        expect(lines.first, contains('no system bus socket'));
        expect(lines.last, contains('NameHasNoOwner'));
      },
    );

    test('a reply inside the default window is not silence', () async {
      // The only case that exercises `_bluezStartWindow` itself, and it has to
      // be asserted through the notice rather than the answer: both arms
      // return `true`, so setting that constant to `Duration.zero` left a
      // case that only checked the answer green while every probe on a real
      // host timed out, took the fail-open arm and delegated - QUNLEASHED-C
      // back, with nothing red. Verified; it is the survivor that made this
      // case what it is.
      //
      // No `window:` argument, and the delay is a real timer rather than a
      // microtask: a future that completes in a microtask beats a
      // zero-duration timeout, so a fake answering immediately cannot tell the
      // default apart from zero either.
      expect(
        await canReachBlueZVia(
          (_) => Future.delayed(
            const Duration(milliseconds: 20),
            () => DBusStartServiceByNameReply.success,
          ),
        ),
        isTrue,
      );

      expect(said.where((m) => m.contains('did not say whether')), isEmpty);
    });

    test('and stops at the cap, however many causes there are', () async {
      // The cap is what keeps a set keyed on a message from being a volume
      // risk, and without a case it is one constant away from being absent.
      for (final cause in ['first', 'second', 'third', 'fourth']) {
        expect(await _hasNoBus(cause), isFalse);
      }

      final lines = said.where((m) => m.contains('will not start')).toList();
      expect(lines, hasLength(2));
      expect(lines.first, contains('first'));
      expect(lines.last, contains('second'));
    });

    test('says nothing it cannot say, and does not latch it away', () async {
      // The hazard three comments in `linux.dart` claimed to have closed by
      // writing the flag assignment after the emit. It is a no-op: the
      // assignment was unconditional, so a notice raised before
      // `LogService.initialize()` installs the sink was latched away unsaid,
      // and a sink arriving later saw nothing for the life of the isolate.
      // Probed directly before the fix: sink null, call, install sink, call
      // again, zero lines.
      Log.sink = null;
      expect(await _hasNoBus(), isFalse);

      Log.sink = (level, message) => said.add(message);
      expect(await _hasNoBus(), isFalse);

      expect(said.where((m) => m.contains('will not start')), hasLength(1));
    });

    test('and says the quiet-bus line under a flag of its own', () async {
      // A bus that will not answer and a bus that answers no are different
      // facts, they produce opposite answers, and the two lines must not be
      // able to suppress each other. Both in one case because that is the only
      // way to see it: a shared flag is invisible to a test that takes one
      // path, and the two cases above each take one.
      expect(await _refusesBlueZ(), isFalse);
      expect(await _busGoesQuiet(), isTrue);

      expect(said.where((m) => m.contains('will not start')), hasLength(1));
      expect(
        said.where((m) => m.contains('did not say whether')),
        hasLength(1),
      );
    });

    test(
      'says it again after a reset, so the latch is what holds it',
      () async {
        // Otherwise the two cases above would also pass if the lines were
        // emitted never, or once ever and never again in this isolate.
        expect(await _refusesBlueZ(), isFalse);
        debugResetLinuxBleNotices();
        expect(await _refusesBlueZ(), isFalse);

        expect(said.where((m) => m.contains('will not start')), hasLength(2));
      },
    );
  });

  group('a platform with no plugin at all', () {
    test('answers unsupported without asking for one', () async {
      // One line and one constant, but the body it replaces reaches a method
      // channel that has no implementation registered on a platform that got
      // here - which is the same shape of mistake as the Linux one.
      expect(
        await const UnsupportedBlePlatform().availabilityState(),
        uble.AvailabilityState.unsupported,
      );
    });
  });
}
