// STM32WB55 option-bytes (un)packer — Dart port of qFlipper's OptionBytes
// (.sources/qflipper/dfu/device/stm32wb55/optionbytes.{h,cpp}). The 128-byte
// option-bytes region is a set of 32-bit words, each stored twice: NORMAL value
// followed by its COMPLEMENT (bitwise ~ for multi-bit fields, logical ! for
// single-bit flags). We model every field by its byte/bit position and rebuild
// the buffer field-by-field.
//
// Unlike qFlipper (which reconstructs from an uninitialised struct), we retain
// the raw 128 bytes read from the device and only overwrite the fields we
// change, so reserved/unused bits and their complements are preserved exactly.
import 'dart:convert';
import 'dart:typed_data';

import '../../common/log.dart';

class _FieldSpec {
  const _FieldSpec(this.wordOffset, this.bitOffset, this.width, this.logical);

  /// Byte offset of the NORMAL word; the COMPLEMENT word sits at +4.
  final int wordOffset;
  final int bitOffset;
  final int width;

  /// true → complement is logical ! (0/1); false → bitwise ~ masked to width.
  final bool logical;

  int get mask => width >= 32 ? 0xFFFFFFFF : (1 << width) - 1;
}

class OptionBytes {
  OptionBytes._(this._data, this._raw, this.isValid);

  final Map<String, int> _data;
  final Uint8List? _raw; // raw 128 bytes as read from the device, if any
  final bool isValid;

  static const int sizeBytes = 128;

  // Field layout. Offsets/bit positions transcribed from the WB55 reference
  // manual bitfields in optionbytes.h.
  static const Map<String, _FieldSpec> _specs = {
    // Word1 @0
    'RDP': _FieldSpec(0, 0, 8, false),
    'ESE': _FieldSpec(0, 8, 1, true),
    'BOR_LEV': _FieldSpec(0, 9, 3, false),
    'nRST_STOP': _FieldSpec(0, 12, 1, true),
    'nRST_STDBY': _FieldSpec(0, 13, 1, true),
    'nRSTSHDW': _FieldSpec(0, 14, 1, true),
    'IWDGSW': _FieldSpec(0, 16, 1, true),
    'IWDGSTOP': _FieldSpec(0, 17, 1, true),
    'IWDGSTDBY': _FieldSpec(0, 18, 1, true),
    'IWGDSTDBY': _FieldSpec(0, 18, 1, true), // ST's typo duplicate (same bits)
    'WWDGSW': _FieldSpec(0, 19, 1, true),
    'nBOOT1': _FieldSpec(0, 23, 1, true),
    'SRAM2PE': _FieldSpec(0, 24, 1, true),
    'SRAM2RST': _FieldSpec(0, 25, 1, true),
    'nSWBOOT0': _FieldSpec(0, 26, 1, true),
    'nBOOT0': _FieldSpec(0, 27, 1, true),
    'AGC_TRIM': _FieldSpec(0, 29, 3, false),
    // Word2 @8
    'PCROP1A_STRT': _FieldSpec(8, 0, 9, false),
    // Word3 @16
    'PCROP1A_END': _FieldSpec(16, 0, 9, false),
    'PCROP_RDP': _FieldSpec(16, 31, 1, true),
    // Word4 @24 (byte fields)
    'WRP1A_STRT': _FieldSpec(24, 0, 8, false),
    'WRP1A_END': _FieldSpec(24, 16, 8, false),
    // Word5 @32 (byte fields)
    'WRP1B_STRT': _FieldSpec(32, 0, 8, false),
    'WRP1B_END': _FieldSpec(32, 16, 8, false),
    // Word6 @40
    'PCROP1B_STRT': _FieldSpec(40, 0, 9, false),
    // Word7 @48
    'PCROP1B_END': _FieldSpec(48, 0, 9, false),
    // Word8 @104
    'IPCCDBA': _FieldSpec(104, 0, 14, false),
    // Word9 @112
    'SFSA': _FieldSpec(112, 0, 8, false),
    'FSD': _FieldSpec(112, 8, 1, true),
    'DDS': _FieldSpec(112, 12, 1, true),
    // Word10 @120
    'SBRV': _FieldSpec(120, 0, 18, false),
    'SBRSA': _FieldSpec(120, 18, 5, false),
    'BRSD': _FieldSpec(120, 23, 1, true),
    'SNBRSA': _FieldSpec(120, 25, 5, false),
    'NBRSD': _FieldSpec(120, 30, 1, true),
    'C2OPT': _FieldSpec(120, 31, 1, true),
  };

  static OptionBytes invalid() => OptionBytes._({}, null, false);

  /// Parses the 128 bytes read from the device into NORMAL field values.
  factory OptionBytes.fromDeviceData(Uint8List data) {
    if (data.length != sizeBytes) {
      Log.error('[DFU] unexpected option-bytes size ${data.length}');
      return invalid();
    }
    final bd = ByteData.sublistView(data);
    final map = <String, int>{};
    _specs.forEach((name, s) {
      map[name] = _readBits(bd, s.wordOffset, s.bitOffset, s.width);
    });
    return OptionBytes._(map, Uint8List.fromList(data), true);
  }

  /// Parses the option-bytes text file from the firmware bundle: lines of
  /// `FIELD:0xVALUE:...`.
  factory OptionBytes.fromText(String text) {
    final map = <String, int>{};
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final tokens = line.split(':');
      if (tokens.length != 3) {
        Log.error('[DFU] malformed option-bytes line: "$line"');
        return invalid();
      }
      final field = tokens[0].trim();
      final value = int.tryParse(
        tokens[1].trim().replaceFirst(RegExp(r'^0[xX]'), ''),
        radix: 16,
      );
      if (value == null || !_specs.containsKey(field)) {
        Log.error('[DFU] illegal option-bytes field/value: "$line"');
        return invalid();
      }
      map[field] = value;
    }
    return OptionBytes._(map, null, map.isNotEmpty);
  }

  int value(String field) => _data[field] ?? 0xFFFFFFFF;

  void setValue(String field, int v) {
    if (!_specs.containsKey(field)) {
      Log.info('[DFU] illegal option-bytes field: $field');
      return;
    }
    _data[field] = v;
  }

  /// Fields in [other] whose value differs from this one (or is missing here).
  Map<String, int> compare(OptionBytes other) {
    final diff = <String, int>{};
    other._data.forEach((field, right) {
      final left = _data[field];
      if (left == null || left != right) diff[field] = right;
    });
    return diff;
  }

  /// A copy with [diff] applied (retains the raw device buffer for serializing).
  OptionBytes corrected(Map<String, int> diff) {
    final copy = OptionBytes._(
      Map<String, int>.from(_data),
      _raw == null ? null : Uint8List.fromList(_raw),
      isValid,
    );
    diff.forEach(copy.setValue);
    return copy;
  }

  /// Serializes back to 128 bytes for download. Starts from the retained device
  /// buffer (preserving reserved bits) and writes each field's NORMAL +
  /// COMPLEMENT words.
  Uint8List toData() {
    final out = Uint8List(sizeBytes);
    if (_raw != null) out.setAll(0, _raw);
    final bd = ByteData.sublistView(out);
    _data.forEach((field, v) {
      final s = _specs[field];
      if (s == null) return;
      _writeBits(bd, s.wordOffset, s.bitOffset, s.width, v);
      final comp = s.logical ? (v == 0 ? 1 : 0) : ((~v) & s.mask);
      _writeBits(bd, s.wordOffset + 4, s.bitOffset, s.width, comp);
    });
    return out;
  }

  static int _readBits(ByteData bd, int wordOffset, int bitOffset, int width) {
    final word = bd.getUint32(wordOffset, Endian.little);
    final mask = width >= 32 ? 0xFFFFFFFF : (1 << width) - 1;
    return (word >> bitOffset) & mask;
  }

  static void _writeBits(
    ByteData bd,
    int wordOffset,
    int bitOffset,
    int width,
    int value,
  ) {
    final mask = width >= 32 ? 0xFFFFFFFF : (1 << width) - 1;
    var word = bd.getUint32(wordOffset, Endian.little);
    word &= ~(mask << bitOffset) & 0xFFFFFFFF;
    word |= (value & mask) << bitOffset;
    bd.setUint32(wordOffset, word & 0xFFFFFFFF, Endian.little);
  }
}
