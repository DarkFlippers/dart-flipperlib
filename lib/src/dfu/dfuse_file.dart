// DfuSe (.dfu) container parser — Dart port of qFlipper's DfuseFile
// (.sources/qflipper/dfu/dfusefile.cpp). Parses the firmware.dfu produced by
// the Flipper update bundle into per-image elements (address + bytes) that the
// DfuSe download routine flashes. All multi-byte fields are little-endian.
import 'dart:typed_data';

import '../common/log.dart';

class DfuseElement {
  DfuseElement(this.address, this.data);
  final int address;
  final Uint8List data;
  int get size => data.length;
}

class DfuseImage {
  DfuseImage(this.alternateSetting, this.targetName);
  final int alternateSetting;
  final String targetName;
  final List<DfuseElement> elements = [];
}

class DfuseFile {
  DfuseFile._(this.images, this.isValid);

  final List<DfuseImage> images;
  final bool isValid;

  static const int _suffixSize = 16;

  /// Parses [bytes]; the result's [isValid] reports prefix/suffix/CRC validity.
  factory DfuseFile.parse(Uint8List bytes) {
    final images = <DfuseImage>[];
    final r = _Reader(bytes);

    // ── Prefix (11 bytes) ──
    if (bytes.length < 11) {
      Log.error('[DFU] DfuSe file too short');
      return DfuseFile._(images, false);
    }
    final signature = String.fromCharCodes(r.read(5));
    if (signature != 'DfuSe') {
      Log.info('[DFU] not a valid DfuSe file (sig="$signature")');
      return DfuseFile._(images, false);
    }
    r.u8(); // bVersion
    final dfuImageSize = r.u32();
    final bTargets = r.u8();

    if (dfuImageSize != bytes.length - _suffixSize) {
      Log.error('[DFU] DfuSe image size mismatch');
      return DfuseFile._(images, false);
    }

    // ── Images ──
    for (var t = 0; t < bTargets; t++) {
      final img = _readImage(r);
      if (img == null) return DfuseFile._(images, false);
      images.add(img);
    }

    // ── Suffix (16 bytes) ──
    r.u16(); // bcdDevice
    r.u16(); // idProduct
    r.u16(); // idVendor
    r.u16(); // bcdDFU
    final sig = r.read(3); // 'UFD' little-endian → 0x44 0x46 0x55
    final ucDfuSignature = sig[0] | (sig[1] << 8) | (sig[2] << 16);
    final bLength = r.u8();
    final dwCRC = r.u32();
    if (ucDfuSignature != 0x444655 || bLength != _suffixSize) {
      Log.error('[DFU] invalid DfuSe suffix');
      return DfuseFile._(images, false);
    }

    // ── CRC over everything but the trailing dwCRC field ──
    if (_crc(bytes) != dwCRC) {
      Log.error('[DFU] DfuSe checksum mismatch');
      return DfuseFile._(images, false);
    }

    return DfuseFile._(images, true);
  }

  static DfuseImage? _readImage(_Reader r) {
    final signature = String.fromCharCodes(r.read(6));
    if (signature != 'Target') {
      Log.info('[DFU] not a valid DfuSe target image');
      return null;
    }
    final alternateSetting = r.u8();
    r.u32(); // bTargetNamed
    final nameBytes = r.read(255);
    final nameEnd = nameBytes.indexOf(0);
    final targetName = String.fromCharCodes(
      nameEnd >= 0 ? nameBytes.sublist(0, nameEnd) : nameBytes,
    );
    r.u32(); // dwTargetSize
    final dwNbElements = r.u32();

    final img = DfuseImage(alternateSetting, targetName);
    for (var i = 0; i < dwNbElements; i++) {
      final address = r.u32();
      final size = r.u32();
      img.elements.add(DfuseElement(address, r.read(size)));
    }
    return img;
  }

  // CRC32 (reflected, poly 0xEDB88320) seeded with 0xFFFFFFFF over all bytes
  // except the final 4 (dwCRC). No final XOR — matches the DfuSe convention and
  // qFlipper's generateCRC byte-for-byte.
  static int _crc(Uint8List bytes) {
    final lut = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var val = i;
      for (var j = 0; j < 8; j++) {
        val = (val & 1) != 0 ? 0xEDB88320 ^ (val >> 1) : val >> 1;
      }
      lut[i] = val;
    }
    var val = 0xFFFFFFFF;
    final end = bytes.length - 4;
    for (var i = 0; i < end; i++) {
      val = (lut[(val ^ bytes[i]) & 0xFF] ^ (val >> 8)) & 0xFFFFFFFF;
    }
    return val;
  }
}

class _Reader {
  _Reader(this._bytes) : _data = ByteData.sublistView(_bytes);
  final Uint8List _bytes;
  final ByteData _data;
  int _pos = 0;

  int u8() => _bytes[_pos++];

  int u16() {
    final v = _data.getUint16(_pos, Endian.little);
    _pos += 2;
    return v;
  }

  int u32() {
    final v = _data.getUint32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  Uint8List read(int n) {
    final out = Uint8List.sublistView(_bytes, _pos, _pos + n);
    _pos += n;
    return Uint8List.fromList(out);
  }
}
