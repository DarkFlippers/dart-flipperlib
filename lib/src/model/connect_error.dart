library;

/// What a session with no transport raises, and what a transport raises once
/// it is closed.
///
/// Constants rather than literals at the throw sites for the reason
/// `FlipperClient.sessionLimitMessage` is one, and qUnleashed#363 is what it
/// cost here. Note what does and does not keep them honest: the needles below
/// are a third, hand-lowercased copy, so it is `connect_error_test.dart`
/// classifying these constants - not their sitting in this file - that makes
/// rewording either one fail a test instead of silently falling back to
/// [FlipperConnectErrorKind.unknown].
///
/// They live here rather than on `FlipperClient` because the transports throw
/// the second one and sit below the client in the import graph.
const String noActiveTransportMessage = 'No active transport';

/// See [noActiveTransportMessage].
const String transportClosedMessage = 'Transport closed';

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
    // The two that name the near end of the link rather than the peer: the
    // transport was torn down under an operation somebody was waiting on.
    // They describe the same event the needles above do, seen from this side,
    // so they belong in the same bucket - a link that came up and died a
    // second later is a device out of range, and the dialog should say so.
    //
    // Kept in step with `FlipperClient.isLinkDropError`, which already counts
    // both as a drop an automatic reconnect can make whole again. The two
    // disagreeing is the bug: a caller that awaits `connect` and then
    // `switchToRpcMode` finds no transport in the gap between them when the
    // link dies there, and `No active transport` reaching this function fell
    // through to `unknown` - so a user at the edge of range was shown the
    // generic "connection failed" instead of the one about range.
    // qUnleashed#363.
    'no active transport',
    'transport closed',
  ])) {
    return FlipperConnectErrorKind.deviceUnreachable;
  }

  return FlipperConnectErrorKind.unknown;
}
