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

  /// This library's own cap, and the one kind here that does not come from a
  /// platform BLE stack. Until qUnleashed#120 it hit no needle at all - `too
  /// many` is not in the sentence and `disconnect one first` does not contain
  /// `disconnected` - so it fell through to `unknown` and the user was told
  /// only that the connection failed, with no mention of the link they would
  /// have to let go of.
  group('this library running out of links', () {
    // The anchor. Everything else here is a hand-written approximation of
    // what `_connectLocked` throws; this is the string itself, so rewording
    // it fails here rather than silently going back to `unknown`.
    test('is read from the message the client actually throws', () {
      expect(
        classifyConnectError(FlipperClient.sessionLimitMessage),
        FlipperConnectErrorKind.sessionLimit,
      );
    });

    // Which is how it arrives: callers classify the caught object, and
    // StateError wraps the message in "Bad state: ...".
    test('survives being wrapped in a StateError', () {
      expect(
        classifyConnectError(StateError(FlipperClient.sessionLimitMessage)),
        FlipperConnectErrorKind.sessionLimit,
      );
    });

    for (final message in const [
      'Only 2 links can be held at once; disconnect one first',
      'Bad state: Only 4 links can be held at once; disconnect one first',
    ]) {
      test('is read from "$message"', () {
        expect(
          classifyConnectError(message),
          FlipperConnectErrorKind.sessionLimit,
        );
      });
    }

    // The near-miss that made this fall through for so long: `deviceUnreachable`
    // matches `disconnected`, and the sentence says `disconnect one first`.
    test('is not read as the device being unreachable', () {
      expect(
        classifyConnectError(FlipperClient.sessionLimitMessage),
        isNot(FlipperConnectErrorKind.deviceUnreachable),
      );
    });

    // The order of the two "no room" blocks is the behaviour. They have
    // different fixes - unpair something in system settings, versus let a
    // link go in the picker - so one must not absorb the other.
    test('is not the OS pairing limit', () {
      expect(
        classifyConnectError(FlipperClient.sessionLimitMessage),
        isNot(FlipperConnectErrorKind.tooManyDevices),
      );
      expect(
        classifyConnectError('too many paired devices'),
        FlipperConnectErrorKind.tooManyDevices,
      );
    });
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

  // A caller that awaits `connect` and then switches the session to RPC -
  // which is what opening a link is - fails with one of these when the link
  // dies in the gap between the two. Not something a BLE stack said: this
  // library's own sentence for a transport that is no longer there. It
  // matched no needle, so it reached the dialog as `unknown` and told
  // somebody at the edge of range nothing about range. qUnleashed#363.
  group('the link dropping under a connect', () {
    // The anchors. Both sentences are raised from a dozen places - fourteen of
    // which read these constants, six of which spell them out (see below) - so
    // rewording one fails here rather than quietly going back to `unknown`.
    for (final message in const [
      noActiveTransportMessage,
      transportClosedMessage,
    ]) {
      test('is read from "$message"', () {
        expect(
          classifyConnectError(message),
          FlipperConnectErrorKind.deviceUnreachable,
        );
      });
    }

    // The sentences as the six sites hold them, which is not how the constants
    // are spelled: both embed a constant's words inside a longer phrase, and
    // one lowercases them. They are read by two predicates - this one for the
    // dialog, `isLinkDropError` for whether a reconnect can make the failure
    // whole - and the two used to match separately, with different case
    // policies, so these sites were a drop to one and not to the other. Both
    // now go through `namesLinkDrop`; asserting on both here is what holds
    // them together, and asserting on the literals rather than the constants
    // is what catches a site reworded away from them. qUnleashed#366.
    for (final sentence in const [
      // `client.dart` x2, `session/session.dart`.
      'Cannot fetch device info: no active transport',
      // `transport/ble/link.dart` x3.
      'BLE transport closed',
    ]) {
      test('is read from "$sentence" by both readings', () {
        expect(
          classifyConnectError(sentence),
          FlipperConnectErrorKind.deviceUnreachable,
        );
        expect(
          FlipperClient().isLinkDropError(StateError(sentence)),
          isTrue,
          reason: 'a reconnect can make this one whole again',
        );
      });
    }

    // Case is not a fact about the link, so neither reading may turn on it.
    // `isLinkDropError` is the one that did: `classifyConnectError` lowercases
    // its input before `namesLinkDrop` ever sees it, so the classifier half of
    // this cannot fail and is here only to say the two agree.
    test('is read whatever case the sentence arrives in', () {
      for (final sentence in const [
        'NO ACTIVE TRANSPORT',
        'Transport Closed',
      ]) {
        expect(namesLinkDrop(sentence), isTrue, reason: sentence);
        expect(
          FlipperClient().isLinkDropError(StateError(sentence)),
          isTrue,
          reason: sentence,
        );
        expect(
          classifyConnectError(sentence),
          FlipperConnectErrorKind.deviceUnreachable,
        );
      }
    });

    // The new check sits below pairing and busy, where the needles it replaced
    // sat. Block order is the behaviour in this function, so it is asserted
    // rather than left to the reader of the diff.
    test('loses to a sentence that also names a pairing fault', () {
      expect(
        classifyConnectError('PairingTimeout: transport closed'),
        FlipperConnectErrorKind.pairingIncomplete,
      );
    });

    test('loses to a sentence that also says the stack is busy', () {
      expect(
        classifyConnectError('OperationInProgress: no active transport'),
        FlipperConnectErrorKind.busy,
      );
    });

    // And a sentence about something else is still not one, which is the half
    // of a shared reading that a widening could quietly take away.
    test('is not read from a firmware error that names no transport', () {
      expect(namesLinkDrop('Storage error: ERROR_STORAGE_DENIED'), isFalse);
      expect(
        FlipperClient().isLinkDropError(
          StateError('Storage error: ERROR_STORAGE_DENIED'),
        ),
        isFalse,
      );
    });

    // Which of the two the library will hand a test by itself: the no-session
    // branch of `FlipperClient.switchToRpcMode`, not the torn-down-session
    // one the incident took - `_requireTransport` needs a session, and a
    // session needs a transport to have been open.
    test('is what a client with no session rejects with', () async {
      await expectLater(
        FlipperClient().switchToRpcMode(),
        throwsA(
          isStateError.having(
            (e) => e.message,
            'message',
            noActiveTransportMessage,
          ),
        ),
      );
    });
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
