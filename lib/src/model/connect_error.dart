library;

enum FlipperConnectErrorKind {
  stalePairing,
  pairingIncomplete,
  bluetoothUnavailable,
  deviceUnreachable,
  tooManyDevices,
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
  ])) {
    return FlipperConnectErrorKind.deviceUnreachable;
  }

  return FlipperConnectErrorKind.unknown;
}
