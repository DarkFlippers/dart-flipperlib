// STM32WB55 FUS (Firmware Upgrade Service) state — Dart port of qFlipper's
// FUSState (.sources/qflipper/dfu/device/stm32wb55/fusstate.{h,cpp}). Read from
// the FUS status register; drives wireless-stack repair decisions. Values and
// normalisation follow qFlipper exactly: ranged statuses collapse to their base
// value via `& 0xFFFFFFF0`, and only the sentinel means "read failed".

abstract final class FusStatus {
  static const int idle = 0x00;
  static const int fwUpgradeOngoing = 0x10;
  static const int fusUpgradeOngoing = 0x20;
  static const int serviceOngoing = 0x30;
  static const int errorOccured = 0xFF;
  static const int invalid = 0x0BADF00D;
}

abstract final class FusError {
  static const int noError = 0x00;
  static const int imageNotFound = 0x01;
  static const int imageCorrupt = 0x02;
  static const int imageNotAuthentic = 0x03;
  static const int notEnoughSpace = 0x04;
  static const int userAbort = 0x05;
  static const int eraseError = 0x06;
  static const int writeError = 0x07;
  static const int stTagNotFound = 0x08;
  static const int customTagNotFound = 0x09;
  static const int authKeyLocked = 0x0A;
  static const int rollBackError = 0x11;
  static const int notRunning = 0xFE;
  static const int unknown = 0xFF;
}

class FusState {
  FusState(int statusByte, int errorByte)
    : status =
          (statusByte == FusStatus.idle ||
              statusByte == FusStatus.errorOccured ||
              statusByte == FusStatus.invalid)
          ? statusByte
          : statusByte & 0xFFFFFFF0,
      error = errorByte;

  const FusState._(this.status, this.error);

  static const FusState invalid = FusState._(
    FusStatus.invalid,
    FusError.unknown,
  );

  final int status;
  final int error;

  bool get isValid => status != FusStatus.invalid;

  String get statusString => switch (status) {
    FusStatus.idle => 'Idle',
    FusStatus.fwUpgradeOngoing => 'Firmware upgrade ongoing',
    FusStatus.fusUpgradeOngoing => 'FUS upgrade ongoing',
    FusStatus.serviceOngoing => 'Service Ongoing',
    FusStatus.errorOccured => 'Error occurred',
    _ => 'Invalid state',
  };

  String get errorString => switch (error) {
    FusError.noError => 'No error',
    FusError.imageNotFound => 'Image not found',
    FusError.imageCorrupt => 'Image corrupt',
    FusError.imageNotAuthentic => 'Image not authentic',
    FusError.notEnoughSpace => 'Not enough space',
    FusError.userAbort => 'User abort',
    FusError.eraseError => 'Erase error',
    FusError.writeError => 'Write error',
    FusError.stTagNotFound => 'ST Microelectronics tag not found',
    FusError.customTagNotFound => 'User-specified tag not found',
    FusError.authKeyLocked => 'Auth key locked',
    FusError.rollBackError => 'Rollback error',
    FusError.notRunning => 'Not running',
    _ => 'Unknown error',
  };

  @override
  String toString() => 'FusState($statusString, $errorString)';
}
