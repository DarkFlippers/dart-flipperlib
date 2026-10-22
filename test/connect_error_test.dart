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
/// A services-missing error whose sentence says nothing about the failure.
///
/// The type arm in `classifyConnectError` is otherwise untestable: the real
/// constructor interpolates `missingCharacteristicsMessage` into the message,
/// so the needle two blocks down catches every genuine instance and deleting
/// the type check changes nothing a case can see. Masking `toString` is what
/// separates the two arms - this reaches `servicesMissing` only by its type.
///
/// `final` because the base is `base`, which requires it.
final class _MaskedServicesMissing extends FlipperServicesMissingError {
  _MaskedServicesMissing() : super(const ['tx(abc)']);

  @override
  String toString() => 'nothing about services at all';
}

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

  // QUNLEASHED-Z, on a Sony Xperia XZ3 running Android 10 with both location
  // permissions revoked. A scan below Android 12 needs `ACCESS_FINE_LOCATION`,
  // and the refusal arrives naming the permission rather than Bluetooth - so
  // it matched nothing and a user who had revoked a permission was told to
  // toggle Bluetooth off and on.
  group('a refused permission', () {
    test('is bluetooth being unavailable', () {
      expect(
        classifyConnectError(
          'UniversalBleException: Code: UniversalBleErrorCode.failed, '
          'Message: Permissions denied: android.permission.ACCESS_FINE_LOCATION, '
          'Details: FAILED',
        ),
        FlipperConnectErrorKind.bluetoothUnavailable,
      );
    });

    // The singular spelling, and why the needle is the plural alone. Both of
    // these are USB, both contain `permission denied`, and neither has
    // anything to do with Bluetooth: the first is somebody dismissing
    // Android's USB prompt, the second is `strerror(EACCES)` on a serial open
    // and the most common Linux serial failure there is.
    //
    // `bluetoothUnavailable` has no USB body to fall back on, so matching
    // these would tell a desktop user with a cable in their hand to turn
    // Bluetooth on - the misclassification this file's own doc opens with,
    // and #120. The literals are the ones the two throw sites hold, so a
    // reword there that reintroduces the collision fails here.
    for (final message in const [
      'USB permission denied or port unavailable',
      'Failed to open /dev/ttyACM0: Permission denied (code 13)',
    ]) {
      test('but a USB refusal is not: "$message"', () {
        expect(
          classifyConnectError(message),
          isNot(FlipperConnectErrorKind.bluetoothUnavailable),
        );
      });
    }

    // QUNLEASHED-1C and -1D. The needle's own comment holds the field data
    // and the argument for its shape; what belongs here is that this reached
    // `unknown` before it - which the events record rather than imply, both
    // carrying `connect.kind: "unknown"` - and why the fixture looks like
    // this.
    //
    // What makes the message hard is the words it does *not* contain: no
    // "denied", no "unauthorized", no "bluetooth is". So it is kept whole
    // rather than trimmed to the part the needle reads, which would be the
    // needle tested against itself.
    //
    // Whole includes the shape. `ConnectionException` wraps
    // `UniversalBleException`, which repeats under `Message:` with
    // `Log.getStackTraceString` concatenated after it, so the inner
    // `SecurityException` appears again under `Stacktrace:`. The frame list
    // is trimmed, as the X/W case two groups down trims its own and for the
    // reason stated there.
    test('is read from Android throwing it at connect time', () {
      expect(
        classifyConnectError(
          'ConnectionException: UniversalBleException: Code: '
          'UniversalBleErrorCode.unknownError, Message: UniversalBleException: '
          'Code: UniversalBleErrorCode.unknownError, Message: '
          'java.lang.SecurityException: Need android.permission.'
          'BLUETOOTH_CONNECT permission for AttributionSource { uid = 10829, '
          'packageName = com.darkflippers.qunleashed, attributionTag = null, '
          'token = android.os.BinderProxy@32b4c3a, next = null }: '
          'GattService registerClient, Details: Cause: null, Stacktrace: '
          'java.lang.SecurityException: Need android.permission.'
          'BLUETOOTH_CONNECT permission for AttributionSource { uid = 10829, '
          'packageName = com.darkflippers.qunleashed, attributionTag = null, '
          'token = android.os.BinderProxy@32b4c3a, next = null }: '
          'GattService registerClient\n'
          '\tat android.os.Parcel.createExceptionOrNull(Parcel.java:2437)\n'
          '\tat android.bluetooth.BluetoothGatt.connect(BluetoothGatt.java:1109)\n'
          '\tat android.os.Looper.loop(Looper.java:313)\n'
          '\tat android.app.ActivityThread.main(ActivityThread.java:8663)\n',
        ),
        FlipperConnectErrorKind.bluetoothUnavailable,
      );
    });

    // The scan permission reaches the same kind, which is the reason the
    // needle stops at the prefix: a dial scans before it connects, so either
    // can be what was refused, and the two want the one sentence this kind
    // has. `startScan` rather than `GattService registerClient` because that
    // is the operation Android names for this one.
    test('is read for the scan permission too', () {
      expect(
        classifyConnectError(
          'java.lang.SecurityException: Need android.permission.BLUETOOTH_SCAN '
          'permission for AttributionSource {...}: startScan',
        ),
        FlipperConnectErrorKind.bluetoothUnavailable,
      );
    });

    // The boundary the needle actually draws, which is the prefix *and* a
    // Bluetooth suffix. Nothing above pins the suffix half: the case below
    // carries no `android.permission.` at all, so it would stay green against
    // a widening to the bare prefix - which is the plausible next loosening,
    // and the one the needle's own comment argues against in prose.
    //
    // Asserted as `unknown` and not as "not bluetoothUnavailable": the weaker
    // form also passes if a later needle files this under `pairingIncomplete`
    // or `deviceUnreachable`, which is a misclassification just as wrong as
    // the one being guarded. Two cases in this file were deleted for exactly
    // that shape; see the services-missing group.
    test('but another android.permission.* refusal is not', () {
      expect(
        classifyConnectError(
          'java.lang.SecurityException: Need '
          'android.permission.READ_EXTERNAL_STORAGE permission for '
          'AttributionSource {...}: openFile',
        ),
        FlipperConnectErrorKind.unknown,
      );
    });

    // The singular spelling asserted as `unknown`, which is what this case
    // alone covers: the USB pair above pins the same word with the weaker
    // `isNot`, for the reason the case above gives. The input is libcore's
    // `SecurityException`, thrown out of `IoBridge` on a socket open, so it
    // also stands as the non-Bluetooth capability the needle must not read -
    // though the case above already fails against a bare `securityexception`
    // needle, being a `SecurityException` itself.
    test('but a SecurityException about something else is not', () {
      expect(
        classifyConnectError(
          'java.lang.SecurityException: Permission denied (missing '
          'INTERNET permission?)',
        ),
        FlipperConnectErrorKind.unknown,
      );
    });
  });

  // QUNLEASHED-Y: the link came up to a device that presented no Flipper
  // service at all - all four characteristics missing, which is Android
  // handing over a stale cached service list rather than any one of them
  // being absent.
  //
  // The three platform cases below it are the same condition seen one layer
  // lower, where no service list arrived at all: bluez resolving nothing, and
  // the Windows connect-time enumeration failing at either level. The two
  // after those are the strings that look like them and are not.
  group('a device with no Flipper service on it', () {
    // The type arm, reached by the only input that can distinguish it. A real
    // instance carries the sentence in its message, so it would classify
    // through the needle whether the type check existed or not - which is
    // what a mutation run deleting the type arm alone shows: every other case
    // here stays green.
    test('is read from the type, not only from its sentence', () {
      expect(
        classifyConnectError(_MaskedServicesMissing()),
        FlipperConnectErrorKind.servicesMissing,
      );
    });

    // What the type carries. `ble_services_missing_test.dart` drives the real
    // throw site and pins the contents against discovery; this pins the one
    // promise the class itself makes about them, which is that the list it
    // hands out cannot be edited under its message.
    test('and hands out a list that cannot be mutated', () {
      final error = FlipperServicesMissingError(const ['overflow(abc)']);

      expect(error.missing, ['overflow(abc)']);
      expect(() => error.missing.add('rx(def)'), throwsUnsupportedError);
    });

    // The sentence without the type, which is the fallback arm. Delete the
    // needle and this case fails; delete the type check as well and the first
    // one goes too, which is what a mutation run over both arms shows. The
    // platform cases below have needles of their own and are unaffected by
    // either.
    //
    // Two cases used to sit in this group asserting `isNot(deviceUnreachable)`
    // and `isNot(stalePairing)` on this input. Delete the branch and the
    // function returns `unknown`, which satisfies both - so they named the
    // distinction the kind exists for and tested nothing, which is the shape
    // CLAUDE.md calls out. The distinction itself is real and belongs here in
    // prose: the device answered, so it is not out of range, and the bond is
    // intact, so the pairing is not stale.
    //
    // The literal rather than the constant, so a reword at the throw site
    // that left the needle behind fails here instead of going quietly back to
    // `unknown`, which has a sentence of its own and so looks like nothing
    // broke. It is also what keeps a `StateError` from an older build of this
    // library classifying the same way.
    //
    // The list after the colon is not read by anything: the needle is the
    // prefix, and there is no branch between a full list and a partial one.
    // A case feeding a one-characteristic list used to sit here claiming to
    // cover that, and could not fail - `ble_services_missing_test.dart` is
    // where a partial list means something, because that is where it is
    // produced.
    test('and from the sentence alone, without the type', () {
      expect(
        classifyConnectError(
          StateError(
            'Missing Flipper BLE characteristics: '
            'tx(19ed82ae-ed21-4c9d-4145-228e62fe0000), '
            'rx(19ed82ae-ed21-4c9d-4145-228e61fe0000), '
            'overflow(19ed82ae-ed21-4c9d-4145-228e63fe0000), '
            'rpcStatus(19ed82ae-ed21-4c9d-4145-228e64fe0000)',
          ),
        ),
        FlipperConnectErrorKind.servicesMissing,
      );
    });

    // The same condition reported by the platform instead of by us, which is
    // the arm the two needles beside the sentence exist for. Both are the
    // field strings whole, so the case asserts that what Sentry received
    // classifies rather than that a needle matches itself.
    //
    // bluez reached this with no service list at all - the throw at
    // `universal_ble_linux.dart` fires on
    // `gattServices.isEmpty && !servicesResolved` - so there was never a
    // characteristic to find missing. QUNLEASHED-1H.
    test('is read from bluez resolving no services', () {
      expect(
        classifyConnectError(
          'UniversalBleException: Code: UniversalBleErrorCode.failed, '
          'Message: Failed to resolve services, Details: null',
        ),
        FlipperConnectErrorKind.servicesMissing,
      );
    });

    // Windows, from the connect-time service enumeration. The prefix is what
    // is read, and the whole point: this call site is the one that means the
    // service list did not arrive.
    //
    // The shape is the one `link.dart` publishes a connect failure in, which
    // is how it actually reaches the classifier - and it carries
    // `disconnected` too, so before the needle existed it classified as the
    // device being out of range. That makes this case the one that pins the
    // block order as well as the needle: move the services block below the
    // unreachable ones and `disconnected` wins again.
    test('is read from the Windows service enumeration failing', () {
      expect(
        classifyConnectError(
          'BLE backend connectionChange disconnected: '
          'Failed to get services: ProtocolError [UNCLASSIFIED (see rawError)] '
          '(link=ble budget=3 txPending=0 rpcSession=none)',
        ),
        FlipperConnectErrorKind.servicesMissing,
      );
    });

    // One level in, and the reason that needle stops before the status word:
    // whichever of the three a characteristic query returns, the service list
    // is unusable and the remedy is the same.
    test('and from its characteristics not arriving either', () {
      expect(
        classifyConnectError(
          'UniversalBleException: Code: UniversalBleErrorCode.failed, '
          'Message: Failed to get characteristics for service '
          '19ed82ae-ed21-4c9d-9daa-d75579e1a388: Unreachable, Details: 1',
        ),
        FlipperConnectErrorKind.servicesMissing,
      );
    });

    // The bare word, which is deliberately *not* this kind. It can only come
    // from `ReadValue`, `WriteValue`, the descriptor pair or
    // `SetNotifiableAsync`, all of which run after the map is built - so the
    // services were found, and this kind's sentence would be false. It is
    // QUNLEASHED-1G, and it stays `unknown` so the reporter keeps collecting
    // it until something says which operation failed.
    //
    // `Details: 1` carries nothing: it is `UniversalBleErrorCode.failed`'s own
    // integer, which `create_flutter_error` substitutes when no details are
    // passed, and not an ATT code.
    test('but a bare GATT rejection after discovery is not', () {
      expect(
        classifyConnectError(
          'UniversalBleException: Code: UniversalBleErrorCode.failed, '
          'Message: ProtocolError, Details: 1',
        ),
        FlipperConnectErrorKind.unknown,
      );
    });

    // The string that keeps the two `failed to get ` needles apart. Collapse
    // them to the shared prefix and this one is swallowed by the services
    // block instead of reaching the kind that clears `_heardBle` - and the
    // prefix would also catch this library's own `Failed to get FUS state`
    // from the recovery runner.
    test('and the same enumeration reaching it is still out of range', () {
      expect(
        classifyConnectError(
          'UniversalBleException: Code: UniversalBleErrorCode.failed, '
          'Message: Failed to get services: Unreachable, Details: 1',
        ),
        FlipperConnectErrorKind.deviceUnreachable,
      );
    });

    // The near miss the colon in that needle exists for. `strerror`'s
    // `ENETUNREACH` is a routing failure, not a Flipper out of range, so
    // "move it closer" would be wrong - and nothing reaches the classifier
    // with it today, which is why it is written down now rather than after.
    test('but a routing failure that merely says the word is not', () {
      expect(
        classifyConnectError('Network is unreachable'),
        FlipperConnectErrorKind.unknown,
      );
    });

    // `Unreachable` is a separate value of the same enum, so the platform has
    // already distinguished a device that did not answer from one whose GATT
    // conversation failed, and the kinds follow that split.
    //
    // One direction only, and worth saying which: widen a needle in the
    // services block to cover `Unreachable` and this fails. The other
    // direction cannot be guarded here - that block runs first, so a needle
    // added to the unreachable list for a string it already claims is dead
    // code.
    test('and is not what Windows says when the device did not answer', () {
      expect(
        classifyConnectError(
          'UniversalBleException: Code: UniversalBleErrorCode.failed, '
          'Message: Unreachable, Details: null',
        ),
        FlipperConnectErrorKind.deviceUnreachable,
      );
    });
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

  // The strings Sentry received on 0.17.0's first day, as it received them.
  //
  // qUnleashed's `_reportUnknownConnect` raises one issue per unclassified
  // string, which makes that list this function's to-do list - and these
  // three were the whole of it. Spelled out whole rather than trimmed to the
  // needle, so the case asserts that the field data classifies and not that
  // the needle matches itself: a needle tested against the message it was cut
  // from passes whatever the surrounding format does next.
  group('a numeric GATT status', () {
    for (final message in const [
      // QUNLEASHED-V, which holds both codes, over three users.
      // `universal_ble`'s own wording, with the status repeated in `Details`.
      'UniversalBleException: Code: UniversalBleErrorCode.unknownError, '
          'Message: Unknown Error 133, Details: Unknown Error 133',
      'UniversalBleException: Code: UniversalBleErrorCode.unknownError, '
          'Message: Unknown Error 147, Details: Unknown Error 147',
      // QUNLEASHED-T, during an automatic reconnect.
      'UniversalBleException: Code: UniversalBleErrorCode.invalidHandle, '
          'Message: Failed to read, Details: 1',
      // QUNLEASHED-13, and the third spelling of the same number. The first
      // two were met with a needle each; this one matched neither and showed
      // the generic dialog to somebody whose Flipper was out of range. It is
      // what the code is read rather than enumerated for.
      'UniversalBleException: Code: UniversalBleErrorCode.unknownError, '
          'Message: Failed to read, Details: 133',
    ]) {
      test('is read from "$message"', () {
        expect(
          classifyConnectError(message),
          FlipperConnectErrorKind.deviceUnreachable,
        );
      });
    }

    // Apple forwards `details: String(nsError.code)` for every error
    // `universal_ble` hands up (`UniversalBleHelper.swift`,
    // `createFlutterError`), so a bare number there is any failure at all.
    // These two are real reports, and they are why the status is checked
    // against a set rather than matched as "a number after a qualifier" -
    // which is a shape this predicate had, briefly.
    //
    // Asserted as `unknown` and not merely "not deviceUnreachable": the
    // weaker form passes against a `classifyConnectError` that answers
    // `unknown` for everything, and `unknown` is also the *point* - it is
    // what `_reportUnknownConnect` collects, which is how 133 and 147 were
    // learned.
    for (final message in const [
      'UniversalBleException: Code: UniversalBleErrorCode.unknownError, '
          'Message: Connection limit reached., Details: 11',
      'UniversalBleException: Code: UniversalBleErrorCode.unknownError, '
          'Message: The operation was cancelled., Details: 5',
    ]) {
      test('an Apple error code is not a GATT status: "$message"', () {
        expect(classifyConnectError(message), FlipperConnectErrorKind.unknown);
      });
    }

    // A word that is not a GATT-status qualifier, or a number that is not a
    // GATT status. The first three carry a qualifier with the wrong number -
    // `WinError` has no left word boundary, bluez's `ATT error: 0x0e` puts
    // digits behind a hex prefix, and `libusb error 4` is the positive form of
    // a libusb code. The rest carry a number with no qualifier at all: `133`
    // alone is four characters of a MAC, and `code` is the desktop serial
    // open's word.
    //
    // `HTTP Error 404: Not Found` is deliberately absent. It does classify as
    // `deviceUnreachable`, through the `not found` needle that predates all of
    // this - and no connect path produces it, so asserting it here would be
    // asserting somebody else's decision about a string this function is never
    // handed.
    for (final message in const [
      'StateError: CM_Get_Parent failed, WinError 1168',
      'UniversalBleException: Code: UniversalBleErrorCode.failed, '
          'Message: Operation failed with ATT error: 0x0e, Details: 14',
      'libusb error 4',
      // A longer number starting with a status we do mean. The literals this
      // replaced were `contains`, so they matched these by prefix - the
      // membership set is what makes the whole number count. Measured both
      // ways before the change.
      'UniversalBleException: Message: Failed to read, Details: 1337',
      'PlatformException(gatt, status 1472)',
      'PlatformException(connect, device 133 is not reachable by name)',
      'Failed to open /dev/ttyACM0: Permission denied (code 13)',
      'USB permission denied or port unavailable',
      'connect to 80:E1:27:00:13:30 failed',
    ]) {
      test('is not read from "$message"', () {
        expect(classifyConnectError(message), FlipperConnectErrorKind.unknown);
      });
    }

    // The shapes no event here has produced, kept in their own loop so the
    // header above stays true of the three that did. A plugin that lets the
    // `PlatformException` through rather than wrapping it writes the status
    // this way; `status 147` and `gatt_error` are in the needle list by
    // symmetry with their neighbours, which means nothing reaches them unless
    // a case does - a mutation over that list would otherwise show both
    // surviving.
    //
    // Each needle sits inside a longer sentence rather than alone, because a
    // case whose whole content is the needle asserts only that `contains`
    // works.
    for (final message in const [
      'PlatformException(gatt, status 133)',
      'PlatformException(gatt, status 147)',
      'android.bluetooth: GATT_ERROR while connecting',
    ]) {
      test('is read from the unobserved shape "$message"', () {
        expect(
          classifyConnectError(message),
          FlipperConnectErrorKind.deviceUnreachable,
        );
      });
    }

    // The one unclassified string on that list that is *meant* to stay
    // unclassified, and the reason this case exists: it looks like the four
    // above and is nothing like them. `java.lang.NullPointerException` from
    // inside `universal_ble`'s Android plugin is the plugin falling over, not
    // a fact about the link - so telling somebody their Flipper is out of
    // range would be an invention. `unknown` is the right answer here, and
    // this pins it against the next pass through this list.
    //
    // QUNLEASHED-X and QUNLEASHED-W are that string; it was two issues rather
    // than one because the message carries a Java stack trace whose line
    // numbers differ per ROM, which is a fingerprint problem in the app and
    // not a classification one.
    test('and a plugin falling over is not one', () {
      // Newline-separated and tab-indented, which is how the event carries
      // it - the plugin concatenates `Log.getStackTraceString` whole. The
      // frame list is trimmed. It makes no difference to this function, which
      // lowercases and looks for substrings; the shape is kept because
      // transcribing an event into a shape it does not have is how a fixture
      // stops describing the thing it was taken from.
      expect(
        classifyConnectError(
          'UniversalBleException: Code: UniversalBleErrorCode.unknownError, '
          'Message: java.lang.NullPointerException, Details: Cause: null, '
          'Stacktrace: java.lang.NullPointerException\n'
          '\tat a2.F0.c(Unknown Source:127)\n'
          '\tat android.os.Handler.handleCallback(Handler.java:938)\n',
        ),
        FlipperConnectErrorKind.unknown,
      );
    });
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
