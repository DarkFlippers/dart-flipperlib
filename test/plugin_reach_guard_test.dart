// That the universal_ble calls which initialise the bluez backend are made
// only where something has decided it is safe to make them.
//
// A guard rather than a budget, in the sense `sentry_import_guard_test.dart`
// means in the parent repo: there is no legacy to drain here and no number to
// lower, so zero tolerance is both the current count and the target. ADR 0004
// is the reason it is a test and not a lint plugin; ADR 0012's scoreboard is a
// different instrument and this is not one.
//
// Why it is load-bearing rather than tidy: universal_ble's Linux backend
// initialises on its first call, and a failed initialisation orphans a
// rejection that reaches the root zone and is reported as a fatal crash
// (QUNLEASHED-Q, QUNLEASHED-C; `ble_access_linux_test.dart` has the
// mechanism). Nothing at a call site can catch it, so the only remedy is not
// to make the call on a machine where it will fail - and that remedy needs
// every such call to be somewhere that can be gated.
//
// What this can and cannot see. It matches text, because flipperlib has no
// `analyzer` dev dependency and ADR 0004 asks for a parser; it requires the
// `UniversalBle.` receiver and strips line comments, which are two independent
// reasons for a match to be real, and that is the whole of its rigour. It
// knows nothing about *when* a call runs - so the ordering group at the bottom
// exists because three of the four members flipperlib reaches are safe only by
// the order of statements inside one method.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The members of `UniversalBle` whose Linux implementation awaits
/// `_ensureInitialized()`, and so can be the first touch that orphans a
/// rejection. Read out of universal_ble 2.3.0's
/// `universal_ble_linux/universal_ble_linux.dart`.
///
/// All seven, not just the one that was reported: any of them reached first on
/// a machine where bluez cannot initialise produces the same crash, so the set
/// is what has to be guarded. `connect` is deliberately absent — the Linux
/// backend's `connect` resolves the device and does not initialise — and that
/// is a fact about the pinned plugin version, which is why the version is
/// named above.
const _initialisingMembers = <String, List<String>>{
  'getBluetoothAvailabilityState': ['lib/src/transport/ble/platform.dart'],
  'enableBluetooth': [],
  'disableBluetooth': [],
  'isScanning': [],
  'getSystemDevices': [
    'lib/src/transport/ble/android.dart',
    'lib/src/transport/ble/ios.dart',
    'lib/src/transport/ble/macos.dart',
  ],
  // Reached from `_scanBleLocked`, after it has read availability through the
  // platform and returned early on anything but `poweredOn`. That ordering is
  // what makes these safe, and it is pinned below.
  'startScan': ['lib/src/client/client.dart'],
  'stopScan': ['lib/src/client/client.dart'],
  // Not a member but a getter, and it belongs in this list rather than in an
  // exemption: subscribing to it reaches `_ensureInitialized` too. The
  // backend's controller is a `UniversalBleStreamController` whose `onListen`
  // awaits `getBluetoothAvailabilityState`
  // (`utils/universal_ble_stream_controller.dart`,
  // `interfaces/universal_ble_platform_interface.dart`), and its
  // `catch (_) {}` swallows the rethrow but not the orphaned completer. An
  // earlier version of this file exempted it on the opposite belief.
  //
  // `onCancel: close` also re-arms `onListen`, so it is not one-shot.
  'availabilityStream': ['lib/src/client/client.dart'],
};

/// Source with line comments removed.
///
/// Needed, not fastidious: this file's first draft matched plain substrings and
/// failed on `android.dart`, which names `getBluetoothAvailabilityState` in a
/// comment explaining why Android must *not* use it. A guard that counts prose
/// is a guard people route around by rewording. `usb_release_test.dart` records
/// the same hazard from the other direction — a source assertion that passed
/// because the span it searched included a comment naming the call.
///
/// Crude on purpose: it cuts from the first `//` on a line, so a `//` inside a
/// string literal takes the rest of that line with it. That can only hide a
/// call, never invent one.
String _withoutComments(String source) => source
    .split('\n')
    .map((line) {
      final at = line.indexOf('//');
      return at == -1 ? line : line.substring(0, at);
    })
    .join('\n');

void main() {
  /// Comments stripped once, at load: every assertion below is a `contains`
  /// over the same text, and stripping per assertion grows with the guard.
  late Map<String, String> code;

  setUpAll(() {
    code = {
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        f.path.replaceAll(r'\', '/'): _withoutComments(f.readAsStringSync()),
    };
    // A guard on the guard: a walk that silently matched nothing would make
    // every expectation below pass.
    expect(
      code,
      contains('lib/src/transport/ble/platform.dart'),
      reason: 'the file walk did not pick up the one file that must be in it',
    );
  });

  List<String> callersOf(String member) => [
    for (final entry in code.entries)
      if (entry.value.contains('UniversalBle.$member')) entry.key,
  ];

  group('the calls that initialise bluez are made only where they are gated', () {
    for (final entry in _initialisingMembers.entries) {
      test('${entry.key} is called only where it is allowed', () {
        expect(
          callersOf(entry.key)..sort(),
          entry.value.toList()..sort(),
          reason:
              'UniversalBle.${entry.key} awaits _ensureInitialized on Linux, so '
              'calling it somewhere nothing has gated reopens QUNLEASHED-Q. '
              'Either route it through BlePlatform, or add the file here with '
              'the argument for why it is safe.',
        );
      });
    }
  });

  group('the gated calls sit after their gate, in the same method', () {
    /// The text of one method body, brace-matched from its signature.
    ///
    /// Bounded on purpose. An earlier version of this group searched from the
    /// signature to end of file, which meant "somewhere after this method
    /// starts" - so moving a plugin call out into any later ungated method
    /// kept it green, and the case claiming a call "left this method" could
    /// not fail for that reason.
    String bodyOf(String source, String signature) {
      final at = source.indexOf(signature);
      expect(at, isNot(-1), reason: '$signature was renamed or reshaped');

      var i = source.indexOf('{', at);
      final open = i;
      var depth = 0;
      for (; i < source.length; i++) {
        if (source[i] == '{') depth++;
        if (source[i] == '}') {
          depth--;
          if (depth == 0) return source.substring(open, i + 1);
        }
      }
      fail('$signature has no matching closing brace');
    }

    /// The gate, then the calls it protects.
    void expectGatedBy(String method, List<String> members) {
      final body = bodyOf(code['lib/src/client/client.dart']!, method);

      final gate = body.indexOf('blePlatform.availabilityState()');
      expect(
        gate,
        isNot(-1),
        reason:
            '$method no longer reads availability through the platform, so the '
            'plugin calls in it are ungated.',
      );

      for (final member in members) {
        final call = body.indexOf('UniversalBle.$member');
        expect(
          call,
          isNot(-1),
          reason:
              'UniversalBle.$member is no longer in $method. It is allowed in '
              'this file only because that method gates it, so it needs a new '
              'argument wherever it went.',
        );
        expect(
          call,
          greaterThan(gate),
          reason:
              'UniversalBle.$member now runs before the availability gate in '
              '$method, so it can be the first touch of the bluez backend on '
              'a machine that has no controller - which is QUNLEASHED-Q.',
        );
      }
    }

    test('the scan gates startScan and stopScan', () {
      // Neither is safe by construction. Move the read below the scan wiring,
      // or add a plugin call above it, and the crash is back with every other
      // case in this suite still green. This is what notices.
      expectGatedBy('Future<void> _scanBleLocked(', ['startScan', 'stopScan']);
    });

    test('the connect wait gates its own subscription', () {
      // `availabilityStream`'s `onListen` reaches `_ensureInitialized`, so
      // subscribing is a first touch like any call. What keeps it safe is that
      // `_awaitBleAvailable` returns on `poweredOn` and on `unsupported`
      // before it subscribes.
      expectGatedBy('Future<void> _awaitBleAvailable(', ['availabilityStream']);
    });

    test('and returns on unsupported rather than subscribing', () {
      // The gate being *above* the subscription is not enough on its own:
      // reading the adapter and then subscribing anyway is what a machine with
      // no controller cannot survive, and that is one deleted `if` away. This
      // is the arm that has to exist, not just precede.
      //
      // Textual, and that is this guard's limit: the behavioural version wants
      // `FlipperClient` to take its `BlePlatform` as a constructor parameter
      // instead of reading the global, which is the target DI pattern (ADR
      // 0002) and a wider change than the fix it would be testing.
      final body = bodyOf(
        code['lib/src/client/client.dart']!,
        'Future<void> _awaitBleAvailable(',
      );

      final arm = body.indexOf('AvailabilityState.unsupported');
      expect(
        arm,
        isNot(-1),
        reason:
            '_awaitBleAvailable no longer returns early on `unsupported`, so on '
            'a machine with no controller it falls through and subscribes to '
            'availabilityStream - whose onListen is a first touch of the bluez '
            'backend. That is QUNLEASHED-Q by a different door.',
      );
      expect(
        arm,
        lessThan(body.indexOf('UniversalBle.availabilityStream')),
        reason: 'the `unsupported` arm no longer precedes the subscription',
      );
    });
  });
}
