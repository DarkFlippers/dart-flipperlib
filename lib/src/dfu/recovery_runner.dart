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
//
// The host that finds and hands over the device is a DfuUsbBackend: libusb
// enumeration inside this isolate on desktop, or a proxy to the main isolate's
// Android host. Only the acquire / release / presence-wait seams await; every
// transfer in between stays synchronous.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../common/log.dart';
import 'android_backend.dart';
import 'backend.dart';
import 'dfu_detector.dart';
import 'dfuse_device.dart';
import 'dfuse_file.dart';
import 'isolate_proxy.dart';
import 'libusb/libusb.dart';
import 'libusb_host_backend.dart';
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

/// Why recovery stopped. [failure] is set when the host could not reach the
/// device for a reason the user can act on (driver, permission); it is
/// [DfuHostFailure.other] for protocol-level errors.
class RecoveryFailed extends RecoveryMessage {
  const RecoveryFailed(this.error, [this.failure = DfuHostFailure.other]);
  final String error;
  final DfuHostFailure failure;
}

class _RecoveryConfig {
  _RecoveryConfig(this.sendPort, this.request, this.hostPort);
  final SendPort sendPort;
  final RecoveryRequest request;

  /// Present when the host lives on the main isolate (Android).
  final SendPort? hostPort;
}

/// Spawns the recovery isolate and surfaces its progress as a stream. The
/// stream completes after [RecoveryDone] or [RecoveryFailed].
Stream<RecoveryMessage> runRecovery(RecoveryRequest request) {
  final controller = StreamController<RecoveryMessage>();
  final receivePort = ReceivePort();
  Isolate? isolate;

  // On Android the host is bound to the main isolate's platform channels;
  // serve it to the worker over a port. Desktop workers enumerate themselves.
  final host = DfuUsb.host;
  final DfuProxyServer? proxy = host is AndroidDfuBackend
      ? DfuProxyServer(host)
      : null;

  void teardown() {
    receivePort.close();
    proxy?.close();
  }

  void finish(RecoveryMessage message) {
    if (controller.isClosed) return;
    controller.add(message);
    teardown();
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
      _RecoveryConfig(receivePort.sendPort, request, proxy?.sendPort),
      errorsAreFatal: true,
      debugName: 'flipper-dfu-recovery',
    ).then<void>((spawned) => isolate = spawned).catchError((Object e) {
      finish(RecoveryFailed('Failed to start recovery: $e'));
    }),
  );

  controller.onCancel = () {
    isolate?.kill(priority: Isolate.immediate);
    teardown();
    // A killed worker can not release its device; drop it on the host side so
    // the descriptor is not left open under a dead libusb handle.
    if (host is AndroidDfuBackend) unawaited(host.closeAll());
  };
  return controller.stream;
}

Future<void> _recoveryIsolateEntry(_RecoveryConfig cfg) async {
  final send = cfg.sendPort.send;
  try {
    final hostPort = cfg.hostPort;
    final DfuUsbBackend backend = hostPort != null
        ? DfuProxyClient(hostPort)
        : LibusbHostBackend();
    await _runRecovery(cfg.request, backend, send);
    send(const RecoveryDone());
  } on DfuHostException catch (e) {
    Log.error('[Recovery] host failure: $e');
    send(RecoveryFailed(e.message, e.failure));
  } catch (e, st) {
    Log.error('[Recovery] failed: $e\n$st');
    send(RecoveryFailed(e.toString()));
  }
}

Future<void> _runRecovery(
  RecoveryRequest req,
  DfuUsbBackend backend,
  void Function(Object) send,
) async {
  if (!backend.available || Libusb.instance == null) {
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
  await _withDevice(backend, 'set recovery boot mode', (dev) {
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
  await _waitForDfuCycle(backend);
  send(const RecoveryProgress(RecoveryStep.settingBootMode, 100));

  // 2. Install the wireless (radio) stack through the FUS cycle, mirroring
  //    qFlipper's WirelessStackDownloadOperation. Non-fatal — qFlipper proceeds
  //    to the firmware even if this fails (the radio usually survives a
  //    firmware brick).
  final radioBin = req.radioBin;
  if (radioBin != null && radioBin.isNotEmpty) {
    try {
      await _flashWirelessStack(backend, radioBin, req.radioAddress ?? 0, send);
    } on DfuHostException {
      rethrow;
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
  await _withDevice(backend, 'flash firmware', (dev) {
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
  await _withDevice(backend, 'correct option bytes', (dev) {
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

enum _WirelessStatus {
  invalid,
  fusRunning,
  wsRunning,
  errorOccured,
  unhandledState,
}

const int _installTryCount = 3;
const int _checkTryCount = 3;
const Duration _pollInterval = Duration(seconds: 1);
// qFlipper's AbstractOperation timeout: an offline device fails the step only
// after 30 s; while it is present the poll loop waits indefinitely.
const Duration _offlineTimeout = Duration(seconds: 30);

Future<void> _flashWirelessStack(
  DfuUsbBackend backend,
  Uint8List radioBin,
  int addressOverride,
  void Function(Object) send,
) async {
  var installTry = _installTryCount;
  while (true) {
    await _startFus(backend, send);
    await _deleteWirelessStack(backend, send);
    await _downloadWirelessStack(backend, radioBin, addressOverride, send);
    await _upgradeWirelessStack(backend, send);

    var ok = false;
    for (var i = 0; i < _checkTryCount && !ok; i++) {
      await Future<void>.delayed(_pollInterval);
      ok = await _checkWirelessStack(backend, send);
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
Future<void> _startFus(
  DfuUsbBackend backend,
  void Function(Object) send,
) async {
  send(const RecoveryLog('Starting firmware upgrade service (FUS)'));
  await _withDevice(backend, 'start FUS', (dev) {
    final state = dev.fusGetState();
    if (!state.isValid) {
      throw StateError('Failed to get FUS state');
    } else if (state.status == FusStatus.idle &&
        state.error == FusError.noError) {
      send(
        const RecoveryLog('FUS is already running, rebooting for consistency'),
      );
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
  await _waitForDfuCycle(backend);
}

Future<void> _deleteWirelessStack(
  DfuUsbBackend backend,
  void Function(Object) send,
) async {
  send(const RecoveryLog('Deleting old co-processor firmware'));
  await _withDevice(backend, 'delete wireless stack', (dev) {
    if (!dev.fusFwDelete()) {
      throw StateError('Failed to send FW_DELETE command');
    }
  });
  await _waitForWireless(
    backend,
    send,
    failOn: const {_WirelessStatus.wsRunning, _WirelessStatus.errorOccured},
    what: 'removal of the wireless stack',
  );
}

// Recovery::downloadWirelessStack: with no override the image goes right below
// the current secure-flash boundary, `(origin + 0x1000·SFSA − size) & ~0xFFF`.
Future<void> _downloadWirelessStack(
  DfuUsbBackend backend,
  Uint8List radioBin,
  int addressOverride,
  void Function(Object) send,
) async {
  send(const RecoveryProgress(RecoveryStep.flashingRadio, 0));
  await _withDevice(backend, 'flash radio', (dev) {
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

Future<void> _upgradeWirelessStack(
  DfuUsbBackend backend,
  void Function(Object) send,
) async {
  send(const RecoveryLog('Sending FW_UPGRADE command'));
  await _withDevice(backend, 'upgrade wireless stack', (dev) {
    if (!dev.fusFwUpgrade()) {
      throw StateError('Failed to send FW_UPGRADE command');
    }
  });
  // WSRunning is fine here: the freshly installed stack may auto-start.
  await _waitForWireless(
    backend,
    send,
    failOn: const {_WirelessStatus.errorOccured},
    what: 'installation of the wireless stack',
  );
}

Future<bool> _checkWirelessStack(
  DfuUsbBackend backend,
  void Function(Object) send,
) async {
  final ref = await backend.acquire();
  if (ref == null) return false;
  final dev = Stm32Wb55(ref);
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
    dev.close();
    await backend.release(ref);
  }
}

// Recovery::wirelessStatus: any failure to reach the device or read a valid
// state is Invalid, which the poll loops treat as "wait for the next tick".
Future<_WirelessStatus> _wirelessStatus(DfuUsbBackend backend) async {
  final ref = await backend.acquire();
  if (ref == null) return _WirelessStatus.invalid;
  final dev = Stm32Wb55(ref);
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
    dev.close();
    await backend.release(ref);
  }
}

// Port of the 1 s polling loops in WirelessStackDownloadOperation. Undecided
// statuses keep waiting; the device disappearing for more than the operation
// timeout fails the step. Returns on any decisive status not in [failOn].
Future<void> _waitForWireless(
  DfuUsbBackend backend,
  void Function(Object) send, {
  required Set<_WirelessStatus> failOn,
  required String what,
}) async {
  DateTime? absentSince;
  while (true) {
    await Future<void>.delayed(_pollInterval);
    final status = await _wirelessStatus(backend);
    if (status == _WirelessStatus.invalid ||
        status == _WirelessStatus.unhandledState) {
      if (await backend.isPresent()) {
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
Future<void> _waitForDfuCycle(DfuUsbBackend backend) async {
  await backend.waitPresence(false, const Duration(seconds: 10));
  await _waitForDfuReenumeration(backend, timeout: const Duration(seconds: 30));
}

// Acquires a DFU device, runs [body] inside an open transaction, and always
// releases the device reference. Retries acquisition because the device
// re-enumerates after the resets earlier steps trigger. Order matters for the
// Android host: the libusb handle is closed before the descriptor is handed
// back, and the descriptor is handed back before the next acquire.
Future<void> _withDevice(
  DfuUsbBackend backend,
  String what,
  void Function(Stm32Wb55 dev) body,
) async {
  Log.info('[Recovery] acquiring device for: $what');
  final ref = await _acquireDevice(backend);
  final dev = Stm32Wb55(ref);
  try {
    if (!dev.beginTransaction()) {
      throw _openFailure(what, dev.lastOpenError);
    }
    Log.info('[Recovery] transaction started: $what');
    try {
      body(dev);
    } finally {
      dev.endTransaction();
      Log.info('[Recovery] transaction ended: $what');
    }
  } finally {
    dev.close();
    await backend.release(ref);
  }
}

Object _openFailure(String what, int libusbError) {
  return switch (libusbError) {
    libusbErrorNotSupported => DfuHostException(
      DfuHostFailure.driverMissing,
      '$what: the DFU device has no usable driver (libusb: not supported)',
    ),
    libusbErrorAccess => DfuHostException(
      DfuHostFailure.accessDenied,
      '$what: access to the DFU device was denied',
    ),
    _ => StateError('$what: failed to open DFU device'),
  };
}

Future<DfuDeviceRef> _acquireDevice(
  DfuUsbBackend backend, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final ref = await backend.acquire();
    if (ref != null) return ref;
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative || !await backend.waitPresence(true, remaining)) {
      throw StateError('DFU device not found within ${timeout.inSeconds}s');
    }
  }
}

Future<void> _waitForDfuReenumeration(
  DfuUsbBackend backend, {
  Duration timeout = const Duration(seconds: 15),
  Duration settleDelay = const Duration(milliseconds: 750),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative || !await backend.waitPresence(true, remaining)) {
      break;
    }
    // Give the OS time to finish attaching the bootloader interface, then make
    // sure the device is not only listed but openable.
    await Future<void>.delayed(settleDelay);
    if (await backend.isPresent() && await _canOpenDfuDevice(backend)) return;
    if (!DateTime.now().isBefore(deadline)) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
    'DFU device did not become ready within ${timeout.inSeconds}s',
  );
}

Future<bool> _canOpenDfuDevice(DfuUsbBackend backend) async {
  final ref = await backend.acquire();
  if (ref == null) return false;
  final dev = Stm32Wb55(ref);
  try {
    if (!dev.beginTransaction()) {
      // A device that is present but unreachable will not become reachable by
      // waiting; report the cause right away instead of timing out.
      final failure = _openFailure('open DFU device', dev.lastOpenError);
      if (failure is DfuHostException) throw failure;
      return false;
    }
    dev.endTransaction();
    return true;
  } finally {
    dev.close();
    await backend.release(ref);
  }
}
