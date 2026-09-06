// STM32WB55-specific DfuSe operations — Dart port of qFlipper's STM32WB55
// (.sources/qflipper/dfu/device/stm32wb55/stm32wb55.cpp). Adds option-bytes
// read/write, FUS state/commands and version-table reading on top of the plain
// DfuSe protocol. Runs in an isolate (blocking USB I/O).
import 'dart:typed_data';

import '../../common/log.dart';
import '../dfuse_device.dart';
import 'fus_state.dart';
import 'option_bytes.dart';

/// DfuSe alt-setting partitions exposed by the WB55 bootloader.
class WbPartition {
  static const int flash = 0;
  static const int optionBytes = 1;
  static const int otp = 2;
}

// Memory addresses from AN5185 / qFlipper.
const int _optionBytesAddr = 0x1FFF8000;
const int _otpAddr = 0x1FFF7000;
const int _otpMaxSize = 1024;
const int _fusStatusAddr = 0xFFFF0054;
const int _fusStatusSize = 2;
const int _sram2aBase = 0x20030000;
const int _ditFusMagic = 0x0a94656b;

class WbVersionInfo {
  const WbVersionInfo({
    required this.fusVersion,
    required this.wirelessVersion,
  });
  final String fusVersion;
  final String wirelessVersion;

  static const WbVersionInfo unknown = WbVersionInfo(
    fusVersion: '0.0.0',
    wirelessVersion: '0.0.0',
  );
}

class Stm32Wb55 extends DfuseDevice {
  Stm32Wb55(super.ref);

  OptionBytes optionBytes() {
    final data = upload(
      _optionBytesAddr,
      OptionBytes.sizeBytes,
      WbPartition.optionBytes,
    );
    if (data.length != OptionBytes.sizeBytes) {
      Log.error('[DFU] failed to read option bytes');
      return OptionBytes.invalid();
    }
    return OptionBytes.fromDeviceData(data);
  }

  /// Writes option bytes. The device resets on commit, so the download itself
  /// reports failure — that is expected and ignored (qFlipper does the same).
  bool setOptionBytes(OptionBytes ob) {
    download(ob.toData(), _optionBytesAddr, WbPartition.optionBytes);
    return true;
  }

  /// Reads the raw 128-byte option-bytes region (NORMAL+COMPLEMENT words).
  Uint8List readOptionBytesRaw() {
    final data = upload(
      _optionBytesAddr,
      OptionBytes.sizeBytes,
      WbPartition.optionBytes,
    );
    if (data.length != OptionBytes.sizeBytes) {
      Log.error('[DFU] failed to read raw option bytes');
      return Uint8List(0);
    }
    return data;
  }

  /// Writes the raw 128-byte option-bytes region. The device resets on commit,
  /// so the transfer reports failure — expected and ignored.
  bool writeOptionBytesRaw(Uint8List data) {
    download(data, _optionBytesAddr, WbPartition.optionBytes);
    return true;
  }

  Uint8List otpData(int len) {
    final n = len < _otpMaxSize ? len : _otpMaxSize;
    final data = upload(_otpAddr, n, WbPartition.otp);
    if (data.length != n) {
      Log.error('[DFU] failed to read OTP');
      return Uint8List(0);
    }
    return data;
  }

  FusState fusGetState() {
    final data = upload(_fusStatusAddr, _fusStatusSize, WbPartition.flash);
    if (data.length != _fusStatusSize) {
      Log.error('[DFU] failed to read FUS status');
      return FusState.invalid;
    }
    return FusState(data[0], data[1]);
  }

  bool fusFwDelete() => downloadRaw(Uint8List.fromList([0x52]));

  bool fusFwUpgrade() => downloadRaw(Uint8List.fromList([0x53]));

  bool fusStartWirelessStack() => downloadRaw(Uint8List.fromList([0x5A]));

  /// Reads the FUS / wireless-stack versions from the device information table.
  WbVersionInfo versionInfo() {
    final ptr = upload(_sram2aBase, 4, WbPartition.flash);
    if (ptr.length != 4) return WbVersionInfo.unknown;
    final addr = ByteData.sublistView(ptr).getUint32(0, Endian.little);
    if (addr < _sram2aBase) {
      Log.error('[DFU] invalid info-table address 0x${addr.toRadixString(16)}');
      return WbVersionInfo.unknown;
    }

    const size = 56; // max(sizeof FUSDeviceInfoTable, DeviceInfoTable)
    final table = upload(addr, size, WbPartition.flash);
    if (table.length != size) return WbVersionInfo.unknown;

    final magic = ByteData.sublistView(table).getUint32(0, Endian.little);
    if (magic == _ditFusMagic) {
      // FUSDeviceInfoTable: FUSVersion @12, wirelessStackVersion @20.
      return WbVersionInfo(
        fusVersion: _version(table, 12),
        wirelessVersion: _version(table, 20),
      );
    }
    // DeviceInfoTable: FUS.version @4, WirelessStack.version @16.
    return WbVersionInfo(
      fusVersion: _version(table, 4),
      wirelessVersion: _version(table, 16),
    );
  }

  // VersionInfo subtable: [byte0]=build/branch, [1]=sub, [2]=minor, [3]=major.
  String _version(Uint8List table, int offset) {
    final sub = table[offset + 1];
    final minor = table[offset + 2];
    final major = table[offset + 3];
    return '$major.$minor.$sub';
  }
}
