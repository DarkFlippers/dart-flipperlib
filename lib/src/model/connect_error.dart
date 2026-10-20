library;

/// What a session with no transport raises, and what a transport raises once
/// it is closed.
///
/// Constants rather than literals at the throw sites for the reason
/// `FlipperClient.sessionLimitMessage` is one, and qUnleashed#363 is what it
/// cost here. [namesLinkDrop] is what holds the two readings of a dropped link
/// to one answer - it lowercases these two rather than keeping a copy, so a
/// reword moves both readings together. It cannot make a reword *safe*: six
/// sites spell these sentences out as literals, and what catches a reword that
/// leaves them behind is `connect_error_test.dart` asserting on those literals
/// rather than on the constants.
///
/// They live here rather than on `FlipperClient` because the transports throw
/// the second one and sit below the client in the import graph.
const String noActiveTransportMessage = 'No active transport';

/// See [noActiveTransportMessage].
const String transportClosedMessage = 'Transport closed';

/// What the BLE link raises when a connected device presents no Flipper
/// service, or one without the characteristics the RPC runs over.
///
/// A constant for the same reason as the two above, and with a sharper edge:
/// this sentence is the *only* thing distinguishing a device whose GATT cache
/// is stale from any other failed connect, so a reword at the throw site that
/// did not move the needle with it would put the kind back to `unknown` - and
/// nothing would say so, because the dialog has a sentence for `unknown` too.
/// One case in `connect_error_test.dart` spells the literal out rather than
/// reading this constant, for exactly that reason - the others use the
/// constant, which is the right trade for everything except the reword.
/// QUNLEASHED-Y.
///
/// The thrown message appends the list of what was missing, so the needle is
/// this prefix and not the whole sentence.
const String missingCharacteristicsMessage =
    'Missing Flipper BLE characteristics';

/// A connected device that presented no Flipper service, or one without the
/// characteristics the RPC runs over.
///
/// Typed, so [classifyConnectError] reads the fact rather than re-parsing a
/// sentence this library wrote one frame earlier. That is the established
/// shape in this subsystem rather than a new one:
/// `FlipperClient.isLinkDropError` checks `FlipperTransportError` ahead of its
/// own needles, and `FlipperCancelledException`'s doc in `exceptions.dart`
/// already settles the question in as many words - "not a sealed failure
/// hierarchy - ADR 0008 rejects those and this is not one". ADR 0008 rejects
/// sealed hierarchies and result types; one named error for one's own throw
/// is neither.
///
/// [missing] is what was absent, which until now lived only inside a
/// sentence nothing parsed. Nothing reads it yet: the dialog shows one
/// sentence for every shape of this failure, and the field is here so that
/// the next reader of it does not have to re-parse the message.
///
/// It is deliberately *not* claimed that the list separates the two causes.
/// It cannot, twice over. The entries are pre-rendered `name(uuid)` strings,
/// so telling `rpcStatus` alone from the rest means matching text again -
/// the regex moved out of [classifyConnectError] and into the caller. And
/// `missing.length == 4` is ambiguous at the throw site: in `link.dart` the
/// four nulls arise both when no service matched the Flipper UUID at all and
/// when one matched without the characteristics. All four gone is *usually*
/// a stale Android service cache and `rpcStatus` alone *usually* old
/// firmware, but neither is decidable from this field. Typing the entries
/// and carrying service-presence from the throw site is what would make them
/// so, and is a task of its own.
///
/// The message still reads as [missingCharacteristicsMessage] and the needle
/// in [classifyConnectError] still matches it, so a plain `StateError`
/// carrying those words - from an older build of this library, or from
/// anything else that spells them out - classifies the same way.
/// `base`, because this is exported wholesale by the barrel and Dart lets a
/// subclass replace a field with a getter: one override of [missing] or of
/// `message` breaks the derived message, `toString()`, and the needle
/// fallback together. Nothing extends it.
base class FlipperServicesMissingError extends StateError {
  FlipperServicesMissingError(List<String> missing)
    : assert(missing.isNotEmpty, 'nothing missing is not this failure'),
      missing = List.unmodifiable(missing),
      super('$missingCharacteristicsMessage: ${missing.join(', ')}');

  /// What was absent, each as `tx(uuid)` or `rpcStatus(uuid)`.
  final List<String> missing;
}

/// True when [message] names the near end of the link going away.
///
/// The single reading of that condition, shared by [classifyConnectError]
/// below - which dresses it up for a user - and
/// `FlipperClient.isLinkDropError`, which decides whether an automatic
/// reconnect can make the failure whole again. They used to match the same two
/// sentences apart from each other and with different case policies: the
/// classifier lowercased its input, the predicate did a case-sensitive
/// `contains`. So the two sentences that embed a constant's words inside a
/// longer one - `Cannot fetch device info: no active transport` at three
/// sites, `BLE transport closed` at three more - were a drop to one reading
/// and not to the other. qUnleashed#366.
///
/// That divergence is the defect, and it was latent rather than something a
/// user hit: the only caller that acts on the drop reading is
/// `storageWriteChunked`, and every failure that reaches its catch today is
/// either a `FlipperTransportError` (matched by type) or carries a constant
/// whole - the request queue wraps a failed write, and a teardown prefixes
/// `Disconnected:`. Neither of the six sites is on that path. What the two
/// readings disagreeing cost is the next caller, and a reword of either
/// sentence away from the constants' case.
///
/// Case-insensitive because the sentences are written for a person at the
/// throw site, and whether the words land mid-sentence or start one is not a
/// fact about the link. [message] may already be lowercased - both callers
/// hand over a lowered string today - and lowering twice costs nothing, so
/// neither has to know.
bool namesLinkDrop(String message) {
  final lower = message.toLowerCase();
  return lower.contains(_noActiveTransportNeedle) ||
      lower.contains(_transportClosedNeedle);
}

/// The needles [namesLinkDrop] matches, derived from the constants rather than
/// written out again - a hand-lowercased copy is what had to be kept in step
/// by hand, and was not.
final String _noActiveTransportNeedle = noActiveTransportMessage.toLowerCase();
final String _transportClosedNeedle = transportClosedMessage.toLowerCase();

enum FlipperConnectErrorKind {
  stalePairing,
  pairingIncomplete,
  bluetoothUnavailable,
  deviceUnreachable,

  /// The link came up and is useless: no Flipper service on it.
  ///
  /// Separate from [deviceUnreachable] because the device *did* answer, and
  /// separate from [stalePairing] because the bond is intact - what is stale
  /// is Android's cached GATT service list, which a reconnect or a Bluetooth
  /// toggle refreshes and forgetting the device forces. Telling somebody to
  /// move closer, which is what `deviceUnreachable` says, would be wrong
  /// advice for a device sitting next to them. QUNLEASHED-Y.
  servicesMissing,
  tooManyDevices,

  /// This library's own cap on held links, not the platform's.
  ///
  /// [FlipperClient.maxSessions] links may be held at once, and the
  /// [StateError] saying so is the only one in this enum that comes from here
  /// rather than from a BLE stack. It is separate from [tooManyDevices]
  /// because the two have different fixes: the OS pairing limit wants devices
  /// unpaired in system settings, this one wants a link let go of in the
  /// picker. qUnleashed#120.
  sessionLimit,
  busy,
  unknown,
}

FlipperConnectErrorKind classifyConnectError(Object error) {
  // Read before any string is, because this one is ours and carries the fact
  // structurally. The needle further down stays as the fallback for the same
  // words arriving untyped.
  if (error is FlipperServicesMissingError) {
    return FlipperConnectErrorKind.servicesMissing;
  }

  final e = error.toString().toLowerCase();
  bool has(List<String> needles) => needles.any(e.contains);

  if (has([
    'peer removed pairing',
    'removed pairing information',
    'peerremovedpairing',
    'stale-bond',
    'authentication failure',
    'authenticationfailure',
    'encryption/auth',
    'bonding keys mismatch',
  ])) {
    return FlipperConnectErrorKind.stalePairing;
  }
  // Before tooManyDevices, and deliberately: both are "no room for another
  // one", and only this one can be fixed from inside the app. The needles
  // come from FlipperClient.sessionLimitMessage, which is what
  // `_connectLocked` throws - `connect_error_test.dart` classifies that exact
  // string, so rewording it fails there rather than here.
  if (has(['links can be held', 'disconnect one first'])) {
    return FlipperConnectErrorKind.sessionLimit;
  }
  if (has([
    'connectionlimitexceeded',
    'le-device-limit',
    'too many',
    'toomanypaired',
    'paired devices',
  ])) {
    return FlipperConnectErrorKind.tooManyDevices;
  }

  if (has([
    'bluetoothnotenabled',
    'bluetoothnotavailable',
    'bluetoothunauthorized',
    'bluetoothnotallowed',
    'accessdenied',
    'bluetooth is not enabled',
    'bluetooth is powered off',
    'unauthorized',
    'not authorized',
    // A refused runtime permission, which on Android reaches us as the name
    // of the permission and not as anything about Bluetooth: a scan below
    // Android 12 needs `ACCESS_FINE_LOCATION`, and `universal_ble` reports
    // the refusal as `Permissions denied: android.permission.…`. It belongs
    // in this bucket because this bucket's sentence is already the right
    // one - "turn Bluetooth on and allow this app to use it in your system
    // settings" - and because the alternative was `unknown`, which told a
    // user with a revoked permission to toggle Bluetooth. QUNLEASHED-Z.
    //
    // The plural only, which is what was seen. The singular is deliberately
    // absent: as a bare substring it captures two strings on the *USB* path -
    // `USB permission denied or port unavailable` from
    // `transport/usb/android.dart` when somebody dismisses Android's USB
    // prompt, and `Permission denied (code 13)` from the desktop serial open,
    // which is `strerror(EACCES)` and the most common Linux serial failure
    // there is (a user not in `dialout`). Both would land in a kind named for
    // Bluetooth, and this kind has no USB sentence to fall back on, so the
    // dialog would tell a desktop user with a cable to turn Bluetooth on.
    // They reach `unknown` instead, whose USB body says to re-seat the cable.
    //
    // `telemetry.dart` names this hazard class: the needles generic enough to
    // catch a USB failure file it under a kind named for Bluetooth. This
    // would have been the first one matching a sentence flipperlib writes
    // itself rather than a platform string. The cases below pin both.
    'permissions denied',
  ])) {
    return FlipperConnectErrorKind.bluetoothUnavailable;
  }

  if (has([
    'pairingfailed',
    'pairingcancelled',
    'pairingrejected',
    'pairingtimeout',
    'pairingnotallowed',
    'connectionrejected',
    'notpaired',
    'notpairable',
    'insufficientencryption',
    'encryption is insufficient',
    'insufficientauthentication',
    'insufficientauthorization',
    'insufficientkeysize',
    'protectionlevelnotmet',
    'pairing',
  ])) {
    return FlipperConnectErrorKind.pairingIncomplete;
  }

  if (has([
    'connectionalreadyexists',
    'connectioninprogress',
    'operationinprogress',
    'already connected',
    'already exists',
    'in progress',
  ])) {
    return FlipperConnectErrorKind.busy;
  }

  // The same condition as the type check at the top, for those words
  // arriving without the type. Lowered inline rather than hoisted into a
  // file-level needle: the two at the head of this file are hoisted because
  // `namesLinkDrop` is the one place that reads them and two predicates had
  // to agree on it, which is not the shape here - this is read once, from
  // inside `has`, like every other block.
  //
  // This library's own sentence, so it shares no words with any needle above
  // or below and its position here is for reading order, not precedence.
  if (has([missingCharacteristicsMessage.toLowerCase()])) {
    return FlipperConnectErrorKind.servicesMissing;
  }

  // The near end of the link rather than the peer: the transport was torn down
  // under an operation somebody was waiting on. That is the same event the
  // needles below describe, seen from this side, so it belongs in the same
  // bucket - a link that came up and died a second later is a device out of
  // range, and the dialog should say so. A caller that awaits `connect` and
  // then `switchToRpcMode` finds no transport in the gap between them when the
  // link dies there, and `No active transport` reaching this function fell
  // through to `unknown` - so a user at the edge of range was shown the generic
  // "connection failed" instead of the one about range. qUnleashed#363.
  if (namesLinkDrop(e)) {
    return FlipperConnectErrorKind.deviceUnreachable;
  }

  if (has([
    'devicenotfound',
    'connectiontimeout',
    'connectionfailed',
    'devicedisconnected',
    'connectionterminated',
    'operationtimeout',
    'supervision-timeout',
    'peer-initiated',
    'timed out',
    'timeout',
    'out of range',
    'no-reason',
    'not found',
    'disconnected',
    'session setup',
    // Android's GATT status codes, which carry no words of their own beyond
    // whatever the plugin wrapped them in.
    //
    // 133 is `GATT_ERROR` (0x85), the stack's catch-all: out of range, not
    // advertising, the stack out of GATT clients. 147 is not in Android's
    // published list and arrived from a vendor ROM behaving the same way -
    // which handset is not recoverable, because those events carry no
    // `device.family`. Both reached `unknown` and showed the generic
    // "connection failed" to people whose Flipper was simply not in range -
    // the same miss as qUnleashed#363 arriving by a different road.
    // QUNLEASHED-V holds both codes, over three users, and was most of the
    // unclassified reports on 0.17.0's first day.
    //
    // The numeric GATT status codes are read by [_namesGattUnreachable]
    // below, not spelled here: the word, and then the whole number, and then
    // the number has to be one we mean.
    //
    'gatt_error',
    // The handle the stack is holding no longer names anything, which is what
    // a read finds after the link went away under it rather than a condition
    // of its own - so it belongs with being out of range and not in its own
    // bucket. Seen during an automatic reconnect. QUNLEASHED-T.
    'invalidhandle',
  ])) {
    return FlipperConnectErrorKind.deviceUnreachable;
  }

  if (_namesGattUnreachable(e)) {
    return FlipperConnectErrorKind.deviceUnreachable;
  }

  return FlipperConnectErrorKind.unknown;
}

/// Android GATT status codes that mean the device is not reachable.
///
/// 133 is `GATT_ERROR` (0x85), the stack's catch-all: out of range, not
/// advertising, the stack out of GATT clients. 147 is not in Android's
/// published list and arrived from a vendor ROM behaving the same way - which
/// handset is not recoverable, because those events carry no `device.family`.
/// QUNLEASHED-V holds both, over three users.
///
/// A set and not "any number", which is the whole lesson of this predicate's
/// two previous shapes. Matching any qualified number classified every Apple
/// BLE failure, because `universal_ble` forwards
/// `details: String(nsError.code)` for all of them
/// (`UniversalBleHelper.swift`, `createFlutterError`) - so
/// `Connection limit reached., Details: 11` became "move your Flipper closer"
/// and `_reportUnknownConnect` went empty for iOS and macOS. A code that is
/// not in here is better left `unknown`: that is what the reporter collects,
/// and collecting it is how 133 and 147 got here in the first place.
const Set<int> _gattUnreachableStatuses = {133, 147};

/// The qualifier a GATT status arrives behind, and the whole number after it.
///
/// Three spellings reached this function from the field - `Unknown Error 133`
/// from `universal_ble`, `status 133` from a `PlatformException`
/// (QUNLEASHED-V), and `Failed to read, Details: 133` from the Android plugin
/// (QUNLEASHED-13) - and a literal per spelling was the shape before this.
/// Three literals is not the cost; being a `contains` is: `details: 133`
/// matches `Details: 1337` and `Details: 1472` by prefix, so the literals were
/// *wider* than reading the number, not narrower. Measured, both ways.
///
/// `[\s:=]*` because the three differ only in punctuation, which is a
/// plugin's formatting. `allMatches` because a message can carry two numbers
/// and only the second be the status.
final RegExp _gattStatus = RegExp(r'(?:error|status|details)[\s:=]*(\d{1,5})');

/// Whether [lowercased] names a GATT status this kind is for.
///
/// Private, and exercised through [classifyConnectError] like every other
/// needle here - this file has no imports and no `@visibleForTesting`.
bool _namesGattUnreachable(String lowercased) => _gattStatus
    .allMatches(lowercased)
    .any((m) => _gattUnreachableStatuses.contains(int.parse(m.group(1)!)));
