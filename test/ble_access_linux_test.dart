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
// Both reports were machines with no radio, on 0.17.0:
//
//   - QUNLEASHED-Q, Debian: bluez is not installed, so the bus cannot even
//     activate `org.bluez` ("Unit dbus-org.bluez.service not found")
//   - QUNLEASHED-C, the same cause under an older dbus ("Could not activate
//     remote peer 'org.bluez': activation request failed: unknown unit")
//
// and a third is reachable without them: `_waitForAdapter` polls ten times at
// 100ms and throws `Bluetooth adapter unavailable` down the identical path.
//
// So the only fix available to a caller is to not make the call. These tests
// pin that: the short-circuit answers, and the plugin call is not reached.
import 'dart:io';

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
  _CountedLinux({
    required bool adapterPresent,
    this.plugin = uble.AvailabilityState.poweredOn,
  }) : super(hasAdapter: (() => adapterPresent));

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

  group('a Linux machine that has one', () {
    test('asks the plugin and passes its answer through', () async {
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
