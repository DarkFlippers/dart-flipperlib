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
//   - QUNLEASHED-C, Arch on 0.17.1: a radio the kernel lists and no BlueZ to
//     drive it ("Could not activate remote peer 'org.bluez': activation
//     request failed: unknown unit"). `hciN` is created by the kernel and
//     `org.bluez` by a package, so this host passes the kernel read; it
//     crashed once per launch for three weeks with that read in place, which
//     is #443.
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
  _CountedLinux({
    required bool adapterPresent,
    bool bluezReachable = true,
    CanReachBlueZ? canReachBlueZ,
    this.plugin = uble.AvailabilityState.poweredOn,
  }) : super(
         hasAdapter: (() => adapterPresent),
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

    test('asks the plugin anyway when it cannot read the directory', () {
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
      expect(
        await canReachBlueZVia(
          (_) async => throw const SocketException('no system bus socket'),
        ),
        isFalse,
      );
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

    test('asks the plugin anyway when the bus does not answer', () async {
      // The arm that turns this guard off, and like the kernel read's it fails
      // open on purpose: no answer is not an answer, and switching Bluetooth
      // off for a machine that has it is the worse of the two wrong answers.
      // The fault this probe exists for arrives as an error reply in under a
      // millisecond, never as silence.
      expect(
        await canReachBlueZVia(
          (_) => Completer<DBusStartServiceByNameReply>().future,
          window: Duration.zero,
        ),
        isTrue,
      );
    });

    test('never throws against the real bus, whatever the host', () async {
      // Its whole job. The answer is the host's - a Linux runner with a bus
      // may say either, Windows and macOS have no socket to connect to - so
      // this asserts only that it resolves, which is the property the caller
      // depends on. A throw out of here rejects `availabilityState`, and on
      // the first call that is the uncatchable kind.
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
        // different facts about different reads, and mutually exclusive per
        // isolate anyway - a masked /sys fails open, so `hasAdapter()` is true
        // forever and the no-controller branch is never entered. A shared flag
        // would make either line's absence depend on the other's history,
        // including across the cases in this group.
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
      Future<bool> refuse() => canReachBlueZVia(
        (_) async => throw DBusErrorException(
          DBusMethodErrorResponse('org.freedesktop.DBus.Error.NameHasNoOwner'),
        ),
      );

      expect(await refuse(), isFalse);
      expect(await refuse(), isFalse);

      final lines = said.where((m) => m.contains('will not start')).toList();
      expect(lines, hasLength(1));
      expect(lines.single, contains('NameHasNoOwner'));
      expect(lines.single, contains('org.bluez'));
    });

    test('says the bus went quiet, once', () async {
      Future<bool> silence() => canReachBlueZVia(
        (_) => Completer<DBusStartServiceByNameReply>().future,
        window: Duration.zero,
      );

      expect(await silence(), isTrue);
      expect(await silence(), isTrue);

      expect(
        said.where((m) => m.contains('did not say whether')),
        hasLength(1),
      );
    });

    test('and says it under a flag of its own', () async {
      // A bus that will not answer and a bus that answers no are different
      // facts, they produce opposite answers, and the two lines must not be
      // able to suppress each other. Both in one case because that is the only
      // way to see it: a shared flag is invisible to a test that takes one
      // path, and the two cases above each take one.
      expect(
        await canReachBlueZVia(
          (_) async => throw DBusErrorException(
            DBusMethodErrorResponse(
              'org.freedesktop.DBus.Error.NameHasNoOwner',
            ),
          ),
        ),
        isFalse,
      );
      expect(
        await canReachBlueZVia(
          (_) => Completer<DBusStartServiceByNameReply>().future,
          window: Duration.zero,
        ),
        isTrue,
      );

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
        Future<bool> refuse() => canReachBlueZVia(
          (_) async => throw DBusErrorException(
            DBusMethodErrorResponse(
              'org.freedesktop.DBus.Error.NameHasNoOwner',
            ),
          ),
        );

        expect(await refuse(), isFalse);
        debugResetLinuxBleNotices();
        expect(await refuse(), isFalse);

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
