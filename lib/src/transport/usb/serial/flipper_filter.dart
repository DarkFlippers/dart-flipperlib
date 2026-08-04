import 'port_info.dart';

final RegExp _flipRegExp = RegExp('flip_', caseSensitive: false);

bool cdcGrepFlip({
  required String device,
  required String description,
  required String hwid,
}) {
  return _flipRegExp.hasMatch(device) ||
      _flipRegExp.hasMatch(description) ||
      _flipRegExp.hasMatch(hwid);
}

bool cdcPortIsFlipper(ListPortInfo info) {
  return cdcGrepFlip(
    device: info.device,
    description: info.description,
    hwid: info.hwid,
  );
}
