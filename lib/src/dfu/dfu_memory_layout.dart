// DfuSe memory-layout parser — Dart port of qFlipper's DFUMemoryLayout
// (.sources/qflipper/dfu/dfumemorylayout.cpp). Parses the alt-setting string
// descriptor (e.g. "@Internal Flash /0x08000000/256*004Kg") into the page
// banks needed to compute per-page erase addresses.
import '../common/log.dart';

class DfuPageBank {
  DfuPageBank({
    required this.pageCount,
    required this.pageSize,
    required this.type,
  });

  final int pageCount;
  final int pageSize;
  final int type; // trailing page-type char code (e.g. 'g', 'a', 'e')
}

class DfuMemoryLayout {
  DfuMemoryLayout._(this.name, this.address, this.pageBanks);

  final String name;
  final int address;
  final List<DfuPageBank> pageBanks;

  bool get isValid => pageBanks.isNotEmpty;

  /// Parses a descriptor of the form `@Name /0xADDR/COUNT*SIZEUNITTYPE,...`.
  factory DfuMemoryLayout.fromStringDescriptor(String desc) {
    final empty = DfuMemoryLayout._('', 0, const []);

    final fields = desc.split('/');
    if (fields.length != 3) {
      Log.info('[DFU] bad memory-layout descriptor syntax: "$desc"');
      return empty;
    }

    final name = fields[0].trim();
    final address =
        int.tryParse(
          fields[1].trim().replaceFirst(RegExp(r'^0[xX]'), ''),
          radix: 16,
        ) ??
        0;

    final banks = <DfuPageBank>[];
    for (final bank in fields[2].split(',')) {
      final bankFields = bank.split('*');
      if (bankFields.length != 2) {
        Log.info('[DFU] bad page-bank syntax: "$bank"');
        return empty;
      }
      final pageCount = int.tryParse(bankFields.first.trim()) ?? 0;

      // pageSize string is "<digits><unit><type>", e.g. "004Kg": unit is the
      // second-to-last char (K → ×1024), type is the last char, the leading
      // digits are the size.
      final sizeStr = bankFields.last;
      if (sizeStr.length < 2) {
        Log.info('[DFU] bad page-size token: "$sizeStr"');
        return empty;
      }
      final unitChar = sizeStr[sizeStr.length - 2];
      final multiplier = unitChar == 'K' ? 1024 : 1;
      final type = sizeStr.codeUnitAt(sizeStr.length - 1);
      final digits = sizeStr.substring(0, sizeStr.length - 2);
      final pageSize = (int.tryParse(digits) ?? 0) * multiplier;

      banks.add(
        DfuPageBank(pageCount: pageCount, pageSize: pageSize, type: type),
      );
    }

    return DfuMemoryLayout._(name, address, banks);
  }

  /// Page-aligned addresses to erase for the range [start, end). Mirrors the
  /// qFlipper traversal: walks every bank from the partition origin, collecting
  /// page boundaries that fall inside the range.
  List<int> pageAddresses(int start, int end) {
    final ret = <int>[];
    if (start < address || start > end) {
      Log.error('[DFU] erase address error (start=$start end=$end)');
      return ret;
    }
    if (pageBanks.isEmpty) {
      Log.info('[DFU] page banks empty');
      return ret;
    }

    ret.add(start);
    var current = address;
    for (final bank in pageBanks) {
      for (var i = 0; i < bank.pageCount; i++) {
        current += bank.pageSize;
        if (current > start && current < end) {
          ret.add(current);
        } else if (current >= end) {
          return ret;
        }
      }
    }
    return ret;
  }
}
