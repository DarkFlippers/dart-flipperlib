import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `classifyConnectError` decides, and in what order it decides it.
///
/// The classifier matches substrings of whatever the platform BLE stack threw,
/// and several of those substrings nest inside one another — `peer removed
/// pairing` contains `pairing`, `pairingtimeout` contains `timeout`. So the
/// order of the blocks is the behaviour, not an implementation detail: move
/// one and a whole category silently becomes unreachable.
///
/// The app shows a different dialog per kind, so a misclassification is a user
/// being told to turn Bluetooth on when their bond is stale.
void main() {
  group('a stale bond', () {
    // These come from Android GATT and CoreBluetooth respectively. Both also
    // contain "pairing", which the pairingIncomplete block matches - so this
    // pair is what pins that stalePairing is tested first.
    for (final message in const [
      'PlatformException(peer removed pairing information)',
      'GATT error: removed pairing information',
      'PeerRemovedPairing',
      'stale-bond',
      'Authentication failure (0x05)',
      'bonding keys mismatch',
    ]) {
      test('is read from "$message"', () {
        expect(
          classifyConnectError(message),
          FlipperConnectErrorKind.stalePairing,
        );
      });
    }
  });

  group('too many bonded devices', () {
    for (final message in const [
      'ConnectionLimitExceeded',
      'le-device-limit reached',
      'too many paired devices',
      'TooManyPaired',
    ]) {
      test('is read from "$message"', () {
        expect(
          classifyConnectError(message),
          FlipperConnectErrorKind.tooManyDevices,
        );
      });
    }
  });

  group('bluetooth being unavailable', () {
    for (final message in const [
      'BluetoothNotEnabled',
      'BluetoothNotAvailable',
      'BluetoothUnauthorized',
      'AccessDenied',
      'Bluetooth is powered off',
      'not authorized to use Bluetooth',
    ]) {
      test('is read from "$message"', () {
        expect(
          classifyConnectError(message),
          FlipperConnectErrorKind.bluetoothUnavailable,
        );
      });
    }
  });

  group('an incomplete pairing', () {
    for (final message in const [
      'PairingFailed',
      'PairingCancelled',
      'InsufficientEncryption',
      'ProtectionLevelNotMet',
      'NotPaired',
    ]) {
      test('is read from "$message"', () {
        expect(
          classifyConnectError(message),
          FlipperConnectErrorKind.pairingIncomplete,
        );
      });
    }
  });

  group('the device being unreachable', () {
    for (final message in const [
      'DeviceNotFound',
      'ConnectionTimeout',
      'DeviceDisconnected',
      'supervision-timeout',
      'peer-initiated disconnect',
      'device is out of range',
      'session setup failed',
    ]) {
      test('is read from "$message"', () {
        expect(
          classifyConnectError(message),
          FlipperConnectErrorKind.deviceUnreachable,
        );
      });
    }
  });

  group('being busy', () {
    for (final message in const [
      'ConnectionAlreadyExists',
      'OperationInProgress',
      'already connected',
    ]) {
      test('is read from "$message"', () {
        expect(classifyConnectError(message), FlipperConnectErrorKind.busy);
      });
    }
  });

  // The blocks are ordered, and each case below matches at least two of them.
  // Reordering the classifier passes every single-match test above and fails
  // here, which is the point: this group is the one that pins the order.
  group('a message that matches two kinds', () {
    test('is stale pairing before it is an incomplete one', () {
      // Contains "pairing", which pairingIncomplete matches as a catch-all.
      expect(
        classifyConnectError('peer removed pairing information'),
        FlipperConnectErrorKind.stalePairing,
        reason: 'a bond that existed and went away is not a bond never made',
      );
    });

    test('is an incomplete pairing before it is a timeout', () {
      // Contains "timeout", which deviceUnreachable matches.
      expect(
        classifyConnectError('PairingTimeout'),
        FlipperConnectErrorKind.pairingIncomplete,
        reason: 'the pairing timed out, the device was there',
      );
    });

    test('is an incomplete pairing before it is a failed connection', () {
      // Contains "connectionfailed"? No - but "pairingfailed" and
      // "connectionrejected" both sit in pairingIncomplete while the
      // deviceUnreachable block owns the generic connection failures.
      expect(
        classifyConnectError('ConnectionRejected'),
        FlipperConnectErrorKind.pairingIncomplete,
      );
    });

    test('is too many devices before it is an unreachable one', () {
      // "le-device-limit" sits above the generic connection failures, and a
      // full controller is a different thing to tell a user than "not found".
      expect(
        classifyConnectError('ConnectionLimitExceeded: le-device-limit'),
        FlipperConnectErrorKind.tooManyDevices,
      );
    });
  });

  test('is read regardless of case', () {
    expect(
      classifyConnectError('DEVICENOTFOUND'),
      FlipperConnectErrorKind.deviceUnreachable,
    );
    expect(
      classifyConnectError('bluetoothnotenabled'),
      FlipperConnectErrorKind.bluetoothUnavailable,
    );
  });

  test('is taken from any object, not only a string', () {
    // The real callers hand this whatever the platform channel threw.
    expect(
      classifyConnectError(Exception('DeviceNotFound')),
      FlipperConnectErrorKind.deviceUnreachable,
    );
    expect(
      classifyConnectError(StateError('BluetoothNotEnabled')),
      FlipperConnectErrorKind.bluetoothUnavailable,
    );
  });

  group('anything else', () {
    // Falling through to unknown is a real answer: the UI shows the raw
    // message rather than guessing at a cause.
    for (final message in const [
      'something nobody has seen before',
      '',
      'ENOENT',
    ]) {
      test('is unknown, not the nearest guess: "$message"', () {
        expect(classifyConnectError(message), FlipperConnectErrorKind.unknown);
      });
    }
  });
}
