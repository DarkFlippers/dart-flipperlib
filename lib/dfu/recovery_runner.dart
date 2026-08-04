// Full-device recovery over DfuSe, run in a dedicated isolate. The DfuSe layer
// blocks (USB status polling with sleeps), so it must never touch the UI
// isolate. Mirrors qFlipper's FullRepairOperation
// (.sources/qflipper/backend/flipperzero/toplevel/fullrepairoperation.cpp) for
// the steps that are possible from the DFU bootloader: set recovery boot mode,
// install the wireless (radio) stack through the FUS cycle (start FUS →
// FW_DELETE → download at the SFSA-derived address → FW_UPGRADE → version
// check, with retries — qFlipper's WirelessStackDownloadOperation), flash the
// firmware, correct the option bytes, then leave DFU. Post-boot asset/region
// provisioning is left to the normal RPC update flow once the device
// re-enumerates.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../log.dart';
import 'dfu_detector.dart';
import 'dfuse_device.dart';
import 'dfuse_file.dart';
import 'stm32wb55/fus_state.dart';
import 'stm32wb55/option_bytes.dart';
import 'stm32wb55/stm32wb55.dart';

/// Recovery step identifiers reported to the UI.
enum RecoveryStep {
  settingBootMode,
  flashingRadio,
  flashingFirmware,
  correctingOptionBytes,
  restarting,
}

/// Inputs for a full repair, extracted from a Flipper `update.tgz` bundle
/// (`firmware.dfu`, `radio.bin`, and the `update.fuf` manifest's option-byte
/// fields). All file contents are passed by value so the isolate is
/// self-contained. The radio is optional; complete option-byte data is required
/// because recovery mode must be restored to normal boot at the end.
/// [radioAddress] is an explicit override; when null or 0 the target address is
/// computed from the device's SFSA option byte, like qFlipper's full repair.
class RecoveryRequest {
  RecoveryRequest({
    required this.firmwareDfu,
    required this.obReference,
    required this.obCompareMask,
    required this.obWriteMask,
    this.radioBin,
    this.radioAddress,
  });

  final Uint8List firmwareDfu;
  final Uint8List? radioBin;
  final int? radioAddress;
  final Uint8List obReference; // 128 bytes
  final Uint8List obCompareMask; // 128 bytes
  final Uint8List obWriteMask; // 128 bytes
}

/// Applies the update manifest's option-byte correction rule.
///
/// The compare mask decides whether the current value is acceptable, while the
/// write mask limits which bits recovery is allowed to modify.
Uint8List correctedOptionBytes({
  required Uint8List current,
  required Uint8List reference,
  required Uint8List writeMask,
}) {
  _requireOptionBytesSize('current option bytes', current);
  _requireOptionBytesSize('OB reference', reference);
  _requireOptionBytesSize('OB write mask', writeMask);

  final corrected = Uint8List(OptionBytes.sizeBytes);
  for (var i = 0; i < OptionBytes.sizeBytes; i++) {
    corrected[i] =
        (current[i] & (~writeMask[i] & 0xFF)) | (reference[i] & writeMask[i]);
  }
  return corrected;
}

bool optionBytesMatch({
  required Uint8List current,
  required Uint8List reference,
  required Uint8List compareMask,
}) {
  _requireOptionBytesSize('current option bytes', current);
  _requireOptionBytesSize('OB reference', reference);
  _requireOptionBytesSize('OB compare mask', compareMask);

  for (var i = 0; i < OptionBytes.sizeBytes; i++) {
    if ((current[i] & compareMask[i]) != reference[i]) return false;
  }
  return true;
}

void _requireOptionBytesSize(String name, Uint8List data) {
  if (data.length != OptionBytes.sizeBytes) {
    throw ArgumentError(
      '$name must be ${OptionBytes.sizeBytes} bytes, got ${data.length}',
    );
  }
}

// ── Isolate → main messages ──────────────────────────────────────────────────

sealed class RecoveryMessage {
  const RecoveryMessage();
}

class RecoveryProgress extends RecoveryMessage {
  const RecoveryProgress(this.step, this.percent);
  final RecoveryStep step;
  final double percent; // 0..100
}

class RecoveryLog extends RecoveryMessage {
  const RecoveryLog(this.message);
  final String message;
}

class RecoveryDone extends RecoveryMessage {
  const RecoveryDone();
}

class RecoveryFailed extends RecoveryMessage {
  const RecoveryFailed(this.error);
  final String error;
}

class _RecoveryConfig {
  _RecoveryConfig(this.sendPort, this.request);
  final SendPort sendPort;
  final RecoveryRequest request;
}

/// Spawns the recovery isolate and surfaces its progress as a stream. The
/// stream completes after [RecoveryDone] or [RecoveryFailed].
Stream<RecoveryMessage> runRecovery(RecoveryRequest request) {
  final controller = StreamController<RecoveryMessage>();
  final receivePort = ReceivePort();
  Isolate? isolate;

  void finish(RecoveryMessage message) {
    if (controller.isClosed) return;
    controller.add(message);
    receivePort.close();
    unawaited(controller.close());
  }

  receivePort.listen((dynamic message) {
    if (message is RecoveryMessage) {
      if (message is RecoveryDone || message is RecoveryFailed) {
        finish(message);
      } else if (!controller.isClosed) {
        controller.add(message);
      }
    }
  });

  unawaited(
    Isolate.spawn(
      _recoveryIsolateEntry,
      _RecoveryConfig(receivePort.sendPort, request),
      errorsAreFatal: true,
      debugName: 'flipper-dfu-recovery',
    ).then<void>((spawned) => isolate = spawned).catchError((Object e) {
      finish(RecoveryFailed('Failed to start recovery: $e'));
    }),
  );

  controller.onCancel = () {
    isolate?.kill(priority: Isolate.immediate);
    receivePort.close();
  };
  return controller.stream;
}

void _recoveryIsolateEntry(_RecoveryConfig cfg) {
  final send = cfg.sendPort.send;
  try {
    _runRecovery(cfg.request, send);
    send(const RecoveryDone());
  } catch (e, st) {
    Log.error('[Recovery] failed: $e\n$st');
    send(RecoveryFailed(e.toString()));
  }
}

void _runRecovery(RecoveryRequest req, void Function(Object) send) {
  if (!DfuUsb.instance.available) {
    throw StateError('Raw USB (libusb) is not available on this platform');
  }

  _validateOptionBytesRequest(req);
  send(
    RecoveryLog(
      'Starting recovery: firmware=${req.firmwareDfu.length}B, '
      'radio=${req.radioBin?.length ?? 0}B',
    ),
  );

  // 1. Force recovery boot mode before touching flash. Writing option bytes
  //    resets and re-enumerates the device; the next transaction waits for it.
  send(const RecoveryProgress(RecoveryStep.settingBootMode, 0));
  _withDevice('set recovery boot mode', (dev) {
    final optionBytes = dev.optionBytes();
    if (!optionBytes.isValid) {
      throw StateError('Failed to read option bytes before recovery');
    }
    send(
      RecoveryLog(
        'Boot mode before recovery: '
        'nBOOT0=${optionBytes.value('nBOOT0')}, '
        'nSWBOOT0=${optionBytes.value('nSWBOOT0')}',
      ),
    );
    optionBytes.setValue('nBOOT0', 0);
    optionBytes.setValue('nSWBOOT0', 0);
    send(const RecoveryLog('Setting recovery boot mode and resetting device'));
    if (!dev.setOptionBytes(optionBytes)) {
      throw StateError('Failed to set recovery boot mode');
    }
  });
  send(const RecoveryLog('Waiting for DFU device to re-enumerate'));
  _waitForDfuCycle();
  send(const RecoveryProgress(RecoveryStep.settingBootMode, 100));

  // 2. Install the wireless (radio) stack through the FUS cycle, mirroring
  //    qFlipper's WirelessStackDownloadOperation. Non-fatal — qFlipper proceeds
  //    to the firmware even if this fails (the radio usually survives a
  //    firmware brick).
  final radioBin = req.radioBin;
  if (radioBin != null && radioBin.isNotEmpty) {
    try {
      _flashWirelessStack(radioBin, req.radioAddress ?? 0, send);
    } catch (e) {
      send(RecoveryLog('Radio flash failed ($e); continuing with firmware'));
    }
  }
  send(const RecoveryProgress(RecoveryStep.flashingRadio, 100));

  // 3. Flash the firmware (.dfu container).
  send(const RecoveryProgress(RecoveryStep.flashingFirmware, 0));
  final fw = DfuseFile.parse(req.firmwareDfu);
  if (!fw.isValid) throw StateError('Firmware .dfu file is not valid');
  final totalElements = fw.images.fold<int>(
    0,
    (n, img) => n + img.elements.length,
  );
  send(
    RecoveryLog(
      'Firmware: ${req.firmwareDfu.length}B, ${fw.images.length} image(s), '
      '$totalElements element(s)',
    ),
  );
  if (totalElements == 0) {
    throw StateError('Firmware .dfu has no image elements to flash');
  }
  _withDevice('flash firmware', (dev) {
    dev.onProgress = (op, pct) => send(
      RecoveryProgress(
        RecoveryStep.flashingFirmware,
        op == DfuseOperation.download ? 50 + pct / 2 : pct / 2,
      ),
    );
    if (!dev.downloadFile(fw)) throw StateError('Failed to flash firmware');
  });
  send(const RecoveryProgress(RecoveryStep.flashingFirmware, 100));

  // 4. Correct option bytes and return to normal boot. Compare and write masks
  //    have distinct meanings and must not be interchanged.
  send(const RecoveryProgress(RecoveryStep.correctingOptionBytes, 0));
  final reference = req.obReference;
  final compareMask = req.obCompareMask;
  final writeMask = req.obWriteMask;
  _withDevice('correct option bytes', (dev) {
    final current = dev.readOptionBytesRaw();
    if (current.length != OptionBytes.sizeBytes) {
      throw StateError('Failed to read option bytes after flashing');
    }
    if (optionBytesMatch(
      current: current,
      reference: reference,
      compareMask: compareMask,
    )) {
      send(const RecoveryLog('Option bytes already match; leaving DFU'));
      if (!dev.leave()) throw StateError('Failed to leave DFU mode');
      return;
    }

    final corrected = correctedOptionBytes(
      current: current,
      reference: reference,
      writeMask: writeMask,
    );
    if (!optionBytesMatch(
      current: corrected,
      reference: reference,
      compareMask: compareMask,
    )) {
      throw StateError(
        'Option bytes contain mismatches outside the writable mask',
      );
    }

    var changedBytes = 0;
    for (var i = 0; i < OptionBytes.sizeBytes; i++) {
      if (corrected[i] != current[i]) changedBytes++;
    }
    if (changedBytes > 0) {
      send(RecoveryLog('Correcting option bytes ($changedBytes byte(s))'));
      if (!dev.writeOptionBytesRaw(corrected)) {
        throw StateError('Failed to write corrected option bytes');
      }
    } else {
      throw StateError('Option bytes mismatch but no writable bits can fix it');
    }
  });
  send(const RecoveryProgress(RecoveryStep.correctingOptionBytes, 100));
  send(const RecoveryProgress(RecoveryStep.restarting, 100));
}

void _validateOptionBytesRequest(RecoveryRequest req) {
  _requireOptionBytesSize('OB reference', req.obReference);
  _requireOptionBytesSize('OB compare mask', req.obCompareMask);
  _requireOptionBytesSize('OB write mask', req.obWriteMask);

  for (var i = 0; i < OptionBytes.sizeBytes; i++) {
    if ((req.obReference[i] & (~req.obCompareMask[i] & 0xFF)) != 0) {
      throw StateError('OB reference has bits outside compare mask at byte $i');
    }
    if ((req.obWriteMask[i] & (~req.obCompareMask[i] & 0xFF)) != 0) {
      throw StateError('OB write mask exceeds compare mask at byte $i');
    }
  }
}

// ── Wireless-stack (FUS) install, port of qFlipper's
// WirelessStackDownloadOperation + Recovery FUS methods ──────────────────────

enum _WirelessStatus { invalid, fusRunning, wsRunning, errorOccured, unhandledState }

const int _installTryCount = 3;
const int _checkTryCount = 3;
const Duration _pollInterval = Duration(seconds: 1);
// qFlipper's AbstractOperation timeout: an offline device fails the step only
// after 30 s; while it is present the poll loop waits indefinitely.
const Duration _offlineTimeout = Duration(seconds: 30);

void _flashWirelessStack(
  Uint8List radioBin,
  int addressOverride,
  void Function(Object) send,
) {
  var installTry = _installTryCount;
  while (true) {
    _startFus(send);
    _deleteWirelessStack(send);
    _downloadWirelessStack(radioBin, addressOverride, send);
    _upgradeWirelessStack(send);

    var ok = false;
    for (var i = 0; i < _checkTryCount && !ok; i++) {
      sleep(_pollInterval);
      ok = _checkWirelessStack(send);
      if (!ok) {
        send(const RecoveryLog('Wireless stack check failed, retrying'));
      }
    }
    if (ok) return;
    if (--installTry <= 0) {
      throw StateError(
        'Could not install wireless stack after several tries, giving up',
      );
    }
    send(const RecoveryLog('Wireless stack installation failed, retrying'));
  }
}

// Recovery::startFUS. Both success paths reboot the device (leave, or the
// second GET_STATE that actually boots FUS), so the caller must wait for
// re-enumeration.
void _startFus(void Function(Object) send) {
  send(const RecoveryLog('Starting firmware upgrade service (FUS)'));
  _withDevice('start FUS', (dev) {
    final state = dev.fusGetState();
    if (!state.isValid) {
      throw StateError('Failed to get FUS state');
    } else if (state.status == FusStatus.idle &&
        state.error == FusError.noError) {
      send(const RecoveryLog('FUS is already running, rebooting for consistency'));
      if (!dev.leave()) throw StateError('Failed to leave DFU mode');
    } else if (state.status == FusStatus.errorOccured &&
        state.error == FusError.notRunning) {
      send(RecoveryLog('FUS appears not to be running: $state'));
      dev.fusGetState();
    } else {
      throw StateError('Unexpected FUS state: $state');
    }
  });
  send(const RecoveryLog('Waiting for the device to reboot into FUS'));
  _waitForDfuCycle();
}

void _deleteWirelessStack(void Function(Object) send) {
  send(const RecoveryLog('Deleting old co-processor firmware'));
  _withDevice('delete wireless stack', (dev) {
    if (!dev.fusFwDelete()) {
      throw StateError('Failed to send FW_DELETE command');
    }
  });
  _waitForWireless(
    send,
    failOn: const {_WirelessStatus.wsRunning, _WirelessStatus.errorOccured},
    what: 'removal of the wireless stack',
  );
}

// Recovery::downloadWirelessStack: with no override the image goes right below
// the current secure-flash boundary, `(origin + 0x1000·SFSA − size) & ~0xFFF`.
void _downloadWirelessStack(
  Uint8List radioBin,
  int addressOverride,
  void Function(Object) send,
) {
  send(const RecoveryProgress(RecoveryStep.flashingRadio, 0));
  _withDevice('flash radio', (dev) {
    var addr = addressOverride;
    if (addr == 0) {
      final ob = dev.optionBytes();
      if (!ob.isValid) {
        throw StateError('Failed to read option bytes for radio address');
      }
      final origin = dev.partitionOrigin(WbPartition.flash);
      const pageSize = 0x1000;
      final sfsa = ob.value('SFSA');
      addr = (origin + pageSize * sfsa - radioBin.length) & ~(pageSize - 1);
      send(
        RecoveryLog(
          'SFSA value is 0x${sfsa.toRadixString(16)}, '
          'radio target address 0x${addr.toRadixString(16)}',
        ),
      );
    } else {
      send(
        RecoveryLog(
          'Radio target address overridden to 0x${addr.toRadixString(16)}',
        ),
      );
    }
    dev.onProgress = (op, pct) => send(
      RecoveryProgress(
        RecoveryStep.flashingRadio,
        op == DfuseOperation.download ? 50 + pct / 2 : pct / 2,
      ),
    );
    if (!dev.erase(addr, radioBin.length)) {
      throw StateError('Failed to erase radio region');
    }
    if (!dev.download(radioBin, addr, 0)) {
      throw StateError('Failed to flash radio stack');
    }
  });
}

void _upgradeWirelessStack(void Function(Object) send) {
  send(const RecoveryLog('Sending FW_UPGRADE command'));
  _withDevice('upgrade wireless stack', (dev) {
    if (!dev.fusFwUpgrade()) {
      throw StateError('Failed to send FW_UPGRADE command');
    }
  });
  // WSRunning is fine here: the freshly installed stack may auto-start.
  _waitForWireless(
    send,
    failOn: const {_WirelessStatus.errorOccured},
    what: 'installation of the wireless stack',
  );
}

bool _checkWirelessStack(void Function(Object) send) {
  final address = DfuUsb.instance.acquireDevice();
  if (address == null) return false;
  final dev = Stm32Wb55(address);
  try {
    if (!dev.beginTransaction()) return false;
    final info = dev.versionInfo();
    if (!dev.endTransaction()) return false;
    send(
      RecoveryLog(
        'FUS version: ${info.fusVersion}; '
        'wireless stack version: ${info.wirelessVersion}',
      ),
    );
    return info.wirelessVersion != '0.0.0';
  } finally {
    DfuUsb.instance.releaseDevice(address);
  }
}

// Recovery::wirelessStatus: any failure to reach the device or read a valid
// state is Invalid, which the poll loops treat as "wait for the next tick".
_WirelessStatus _wirelessStatus() {
  final address = DfuUsb.instance.acquireDevice();
  if (address == null) return _WirelessStatus.invalid;
  final dev = Stm32Wb55(address);
  try {
    if (!dev.beginTransaction()) return _WirelessStatus.invalid;
    final state = dev.fusGetState();
    if (!state.isValid) {
      dev.endTransaction();
      return _WirelessStatus.invalid;
    }
    if (!dev.endTransaction()) return _WirelessStatus.invalid;
    Log.error('[Recovery] current FUS state: $state');
    if (state.status == FusStatus.idle && state.error == FusError.noError) {
      return _WirelessStatus.fusRunning;
    } else if (state.status == FusStatus.errorOccured) {
      return state.error == FusError.notRunning
          ? _WirelessStatus.wsRunning
          : _WirelessStatus.errorOccured;
    } else {
      return _WirelessStatus.unhandledState;
    }
  } finally {
    DfuUsb.instance.releaseDevice(address);
  }
}

// Port of the 1 s polling loops in WirelessStackDownloadOperation. Undecided
// statuses keep waiting; the device disappearing for more than the operation
// timeout fails the step. Returns on any decisive status not in [failOn].
void _waitForWireless(
  void Function(Object) send, {
  required Set<_WirelessStatus> failOn,
  required String what,
}) {
  DateTime? absentSince;
  while (true) {
    sleep(_pollInterval);
    final status = _wirelessStatus();
    if (status == _WirelessStatus.invalid ||
        status == _WirelessStatus.unhandledState) {
      if (DfuUsb.instance.isPresent()) {
        absentSince = null;
      } else {
        absentSince ??= DateTime.now();
        if (DateTime.now().difference(absentSince) > _offlineTimeout) {
          throw StateError('Failed to finish $what: operation timeout');
        }
      }
      continue;
    }
    if (failOn.contains(status)) {
      throw StateError('Failed to finish $what');
    }
    return;
  }
}

// Waits out a reboot: first for the device to drop off the bus (bounded, in
// case the cycle was missed), then for it to come back openable.
void _waitForDfuCycle() {
  final sw = Stopwatch()..start();
  while (sw.elapsed < const Duration(seconds: 10)) {
    if (!DfuUsb.instance.isPresent()) break;
    sleep(const Duration(milliseconds: 100));
  }
  _waitForDfuReenumeration(timeout: const Duration(seconds: 30));
}

// Acquires a DFU device, runs [body] inside an open transaction, and always
// releases the device reference. Retries acquisition because the device
// re-enumerates after the resets earlier steps trigger.
void _withDevice(String what, void Function(Stm32Wb55 dev) body) {
  Log.info('[Recovery] acquiring device for: $what');
  final address = _acquireDevice();
  final dev = Stm32Wb55(address);
  try {
    if (!dev.beginTransaction()) {
      throw StateError('$what: failed to open DFU device');
    }
    Log.info('[Recovery] transaction started: $what');
    try {
      body(dev);
    } finally {
      dev.endTransaction();
      Log.info('[Recovery] transaction ended: $what');
    }
  } finally {
    DfuUsb.instance.releaseDevice(address);
  }
}

int _acquireDevice({Duration timeout = const Duration(seconds: 15)}) {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final address = DfuUsb.instance.acquireDevice();
    if (address != null) return address;
    sleep(const Duration(milliseconds: 250));
  }
  throw StateError('DFU device not found within ${timeout.inSeconds}s');
}

void _waitForDfuReenumeration({
  Duration timeout = const Duration(seconds: 15),
  Duration settleDelay = const Duration(milliseconds: 750),
}) {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (DfuUsb.instance.isPresent()) {
      sleep(settleDelay);
      if (DfuUsb.instance.isPresent() && _canOpenDfuDevice()) return;
    }
    sleep(const Duration(milliseconds: 100));
  }
  throw StateError(
    'DFU device did not become ready within ${timeout.inSeconds}s',
  );
}

bool _canOpenDfuDevice() {
  final address = DfuUsb.instance.acquireDevice();
  if (address == null) return false;
  final dev = Stm32Wb55(address);
  try {
    if (!dev.beginTransaction()) return false;
    dev.endTransaction();
    return true;
  } catch (_) {
    return false;
  } finally {
    DfuUsb.instance.releaseDevice(address);
  }
}
