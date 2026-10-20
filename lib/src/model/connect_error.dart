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
    // Each code is spelled with the word before it, and twice, because the
    // bare number is four characters of a MAC, a timeout in milliseconds or a
    // firmware build. `universal_ble` stringifies the status as `Unknown Error
    // 133`; a `PlatformException` carries it as `status 133`. `gatt_error` is
    // the symbolic form, which no event here has produced - it is in the list
    // on the same footing as `devicenotfound` and the rest of this block's
    // platform vocabulary, not on the strength of a report.
    //
    // A substring match and not a prefix one, so `error 1337` lands here too,
    // and so would the sequence buried in a longer blob. Left unanchored:
    // `contains` is the whole vocabulary of this function, and an
    // unrecognised numeric GATT code shown the range dialog is a better wrong
    // answer than the generic one, which says nothing at all.
    'error 133',
    'status 133',
    'error 147',
    'status 147',
    'gatt_error',
    // The handle the stack is holding no longer names anything, which is what
    // a read finds after the link went away under it rather than a condition
    // of its own - so it belongs with being out of range and not in its own
    // bucket. Seen during an automatic reconnect. QUNLEASHED-T.
    'invalidhandle',
  ])) {
    return FlipperConnectErrorKind.deviceUnreachable;
  }

  return FlipperConnectErrorKind.unknown;
}
