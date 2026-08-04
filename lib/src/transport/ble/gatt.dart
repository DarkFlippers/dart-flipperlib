const String flipperBleServiceUuid = '8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000';
const String flipperBleRxUuid = '19ed82ae-ed21-4c9d-4145-228e61fe0000';
const String flipperBleTxUuid = '19ed82ae-ed21-4c9d-4145-228e62fe0000';

class BleService {
  final String uuid;
  final List<BleChar> characteristics;
  BleService(this.uuid, this.characteristics);
}

class BleChar {
  final String uuid;
  final bool canWrite;
  final bool canWriteNoRsp;
  final bool canNotify;
  final bool canIndicate;
  BleChar(
    this.uuid, {
    required this.canWrite,
    required this.canWriteNoRsp,
    required this.canNotify,
    required this.canIndicate,
  });
}

enum BleConnState { connected, connecting, disconnected }
