// DfuSe (ST DFU extension) protocol over libusb — Dart port of qFlipper's
// DfuseDevice (.sources/qflipper/dfu/dfusedevice.cpp). Synchronous and blocking
// (status polling with sleeps); must run inside a dedicated isolate, never the
// UI isolate. Builds on [UsbDeviceBackend] for the raw control transfers.
import 'dart:io';
import 'dart:typed_data';

import '../common/log.dart';
import 'dfu_memory_layout.dart';
import 'dfuse_file.dart';
import 'libusb/libusb.dart';
import 'usb_device.dart';

enum DfuseOperation { erase, download, upload }

// bmRequestType for class/interface requests.
const int _requestOut =
    libusbEndpointOut |
    libusbRequestTypeClass |
    libusbRecipientInterface; // 0x21
const int _requestIn =
    libusbEndpointIn |
    libusbRequestTypeClass |
    libusbRecipientInterface; // 0xA1

// DFU class requests.
const int _dfuDnload = 1;
const int _dfuUpload = 2;
const int _dfuGetStatus = 3;
const int _dfuClrStatus = 4;
const int _dfuAbort = 6;

// DFU functional descriptor (carries max transfer size at offset 5).
const int _dfuDescriptorLength = 9;
const int _dfuDescriptorType = 0x21;

// Status / state codes (subset used here).
const int _statusOk = 0;
const int _stateDfuIdle = 2;
const int _stateDfuDnbusy = 4;
const int _stateDfuDnloadIdle = 5;

class _DfuStatus {
  const _DfuStatus(this.bStatus, this.bState, this.bwPollTimeout, this.iString);
  final int bStatus;
  final int bState;
  final int bwPollTimeout;
  final int iString;

  static const _DfuStatus undefined = _DfuStatus(0xff, 0xff, 0, 0);
}

class DfuseDevice extends UsbDeviceBackend {
  DfuseDevice(super.ref);

  /// Reports `(operation, percent 0..100)` during long transfers.
  void Function(DfuseOperation op, double percent)? onProgress;

  bool beginTransaction() => open() && claimInterface(0);

  bool endTransaction() {
    final res = releaseInterface(0);
    close();
    return res;
  }

  /// Origin address of the partition behind alt setting [alt].
  int partitionOrigin([int alt = 0]) {
    final layout = DfuMemoryLayout.fromStringDescriptor(
      stringInterfaceDescriptor(alt),
    );
    return layout.address;
  }

  bool erase(int addr, int maxSize) {
    if (!prepare()) return _fail('Failed to prepare the device');

    final layout = DfuMemoryLayout.fromStringDescriptor(
      stringInterfaceDescriptor(0),
    );
    final pageAddresses = layout.pageAddresses(addr, addr + maxSize);
    if (pageAddresses.isEmpty) return _fail('Address list is empty');

    for (final pageAddress in pageAddresses) {
      if (!_erasePage(pageAddress)) return _fail('Failed to erase page');
      final progress = (pageAddress - addr) * 100.0 / maxSize;
      onProgress?.call(DfuseOperation.erase, progress);
    }
    Log.info('[DFU] erase done');
    return true;
  }

  /// Erases then writes every element of a parsed DfuSe file.
  bool downloadFile(DfuseFile file) {
    if (!file.isValid) return _fail('DfuSe file is not valid');

    for (final img in file.images) {
      for (final elem in img.elements) {
        if (!erase(elem.address, elem.size)) {
          return _fail('Failed to erase the memory');
        }
      }
    }
    for (final img in file.images) {
      for (final elem in img.elements) {
        if (!download(elem.data, elem.address, img.alternateSetting)) {
          return _fail('Failed to download element');
        }
      }
    }
    return true;
  }

  /// Raw single-buffer download to the current address pointer (used for FUS
  /// command bytes on STM32WB55). Alt setting 0.
  bool downloadRaw(Uint8List data) {
    if (!setInterfaceAltSetting(0, 0)) {
      return _fail('Failed to set interface alternate setting');
    }
    if (!prepare()) return _fail('Failed to prepare the device');
    if (!controlTransferOut(_requestOut, _dfuDnload, 0, 0, data)) {
      return _fail('Failed to perform raw download request');
    }
    _DfuStatus status;
    do {
      status = _getStatus();
      if (status.bStatus != _statusOk) {
        return _fail('Failed to raw download a buffer');
      }
      _sleep(status.bwPollTimeout);
    } while (status.bState == _stateDfuDnbusy);
    return true;
  }

  /// Downloads [data] to [addr] under alt setting [alt].
  bool download(Uint8List data, int addr, [int alt = 0]) {
    if (!setInterfaceAltSetting(0, alt)) {
      return _fail('Failed to set interface alternate setting');
    }
    if (!prepare()) return _fail('Failed to prepare the device');
    if (!setAddressPointer(addr)) return _fail('Failed to set address pointer');

    final maxTransferSize = _maxTransferSize();
    if (maxTransferSize == null) return _fail('No functional DFU descriptor');
    Log.info('[DFU] device transfer size: $maxTransferSize');

    var totalSize = 0;
    var transaction = 2;
    while (totalSize < data.length) {
      final end = (totalSize + maxTransferSize).clamp(0, data.length);
      final buf = Uint8List.sublistView(data, totalSize, end);
      if (!controlTransferOut(_requestOut, _dfuDnload, transaction, 0, buf)) {
        return _fail('Failed to perform DFU_DNLOAD transfer');
      }
      _DfuStatus status;
      do {
        status = _getStatus();
        if (status.bStatus != _statusOk) {
          return _fail('An error occurred during download phase');
        }
        _sleep(status.bwPollTimeout);
      } while (status.bState != _stateDfuDnloadIdle);

      totalSize += buf.length;
      transaction++;
      onProgress?.call(
        DfuseOperation.download,
        totalSize * 100.0 / data.length,
      );
    }
    Log.info('[DFU] download finished');
    return true;
  }

  /// Uploads [maxSize] bytes from [addr] under alt setting [alt].
  Uint8List upload(int addr, int maxSize, [int alt = 0]) {
    final out = BytesBuilder(copy: false);
    if (!setInterfaceAltSetting(0, alt)) {
      _fail('Failed to set interface alternate setting');
      return Uint8List(0);
    }
    if (!(prepare() && _abort())) {
      _fail('Failed to prepare the device');
      return Uint8List(0);
    }
    if (!setAddressPointer(addr)) {
      _fail('Failed to set address pointer');
      return Uint8List(0);
    }
    _abort();

    final maxTransferSize = _maxTransferSize();
    if (maxTransferSize == null) {
      _fail('No functional DFU descriptor');
      return Uint8List(0);
    }

    var totalSize = 0;
    var transaction = 2;
    while (totalSize < maxSize) {
      final transferSize = (maxSize - totalSize) < maxTransferSize
          ? (maxSize - totalSize)
          : maxTransferSize;
      final buf = controlTransferIn(
        _requestIn,
        _dfuUpload,
        transaction,
        0,
        transferSize,
      );
      out.add(buf);
      totalSize += buf.length;
      transaction++;
      onProgress?.call(DfuseOperation.upload, totalSize * 100.0 / maxSize);
      if (buf.length < transferSize) {
        Log.info('[DFU] upload end of transmission');
        break;
      }
    }
    Log.info('[DFU] upload finished');
    return out.toBytes();
  }

  /// Leaves DFU mode (final empty DNLOAD to the special leave address).
  bool leave() {
    if (!setInterfaceAltSetting(0, 0)) {
      return _fail('Failed to set interface alternate setting');
    }
    if (!(prepare() && _abort())) return _fail('Failed to prepare the device');
    setAddressPointer(0x080FFFFF);
    if (!controlTransferOut(_requestOut, _dfuDnload, 0, 0, Uint8List(0))) {
      return _fail('Failed to perform final DFU_DNLOAD transfer');
    }
    // Returns an error on WB55 anyway — ignored.
    _getStatus();
    return true;
  }

  // ── internals ──────────────────────────────────────────────────────────────

  bool setAddressPointer(int addr) {
    final req = Uint8List(5)
      ..[0] = 0x21
      ..buffer.asByteData().setUint32(1, addr, Endian.little);
    if (!controlTransferOut(_requestOut, _dfuDnload, 0, 0, req)) {
      return _fail('Failed to perform set address request');
    }
    _DfuStatus status;
    do {
      status = _getStatus();
      if (status.bStatus != _statusOk) return _fail('Failed to set address');
      _sleep(status.bwPollTimeout);
    } while (status.bState == _stateDfuDnbusy);
    return true;
  }

  bool _erasePage(int addr) {
    final buf = Uint8List(5)
      ..[0] = 0x41
      ..buffer.asByteData().setUint32(1, addr, Endian.little);
    if (!controlTransferOut(_requestOut, _dfuDnload, 0, 0, buf)) {
      return _fail('Failed to perform DFU_DNLOAD transfer');
    }
    _DfuStatus status;
    do {
      status = _getStatus();
      if (status.bStatus != _statusOk) {
        return _fail('An error occurred during erase phase');
      }
      _sleep(status.bwPollTimeout);
    } while (status.bState == _stateDfuDnbusy);
    return true;
  }

  bool _abort() {
    if (!controlTransferOut(_requestOut, _dfuAbort, 0, 0, Uint8List(0))) {
      return _fail('Unable to issue abort request');
    }
    final status = _getStatus();
    final res = status.bStatus == _statusOk && status.bState == _stateDfuIdle;
    if (!res) return _fail('Unable to reset device to idle state');
    _sleep(status.bwPollTimeout);
    return res;
  }

  bool _clearStatus() =>
      controlTransferOut(_requestOut, _dfuClrStatus, 0, 0, Uint8List(0));

  _DfuStatus _getStatus() {
    const statusLength = 6;
    final buf = controlTransferIn(
      _requestIn,
      _dfuGetStatus,
      0,
      0,
      statusLength,
    );
    if (buf.length != statusLength) {
      Log.info('[DFU] unable to get device status');
      return _DfuStatus.undefined;
    }
    final bwPollTimeout = buf[1] | (buf[2] << 8) | (buf[3] << 16);
    return _DfuStatus(buf[0], buf[4], bwPollTimeout, buf[5]);
  }

  bool prepare() {
    final status = _getStatus();
    if (status.bStatus != _statusOk) {
      Log.error('[DFU] device in error state, resetting');
      if (!_clearStatus()) return _fail('Failed to clear device status');
    } else if (status.bState != _stateDfuIdle) {
      Log.error('[DFU] device not idle, resetting');
      if (!_abort()) return _fail('Failed to abort to idle');
    }
    return true;
  }

  int? _maxTransferSize() {
    final extra = extraInterfaceDescriptor(
      0,
      _dfuDescriptorType,
      _dfuDescriptorLength,
    );
    if (extra.length < _dfuDescriptorLength) return null;
    return extra[5] | (extra[6] << 8);
  }

  bool _fail(String msg) {
    Log.info('[DFU] $msg');
    return false;
  }

  void _sleep(int ms) {
    if (ms > 0) sleep(Duration(milliseconds: ms));
  }
}
