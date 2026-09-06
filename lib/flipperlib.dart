export 'protobuf.dart';
export 'src/client/client.dart';
export 'src/client/api/app.dart';
export 'src/client/api/ble.dart';
export 'src/client/api/desktop.dart';
export 'src/client/api/gpio.dart';
export 'src/client/api/gui.dart';
export 'src/client/api/property.dart';
export 'src/client/api/storage.dart';
export 'src/client/api/system.dart';
export 'src/client/api/usb.dart';
export 'src/model/discovered.dart';
export 'src/model/enums.dart';
export 'src/model/device.dart';
export 'src/model/exceptions.dart';
export 'src/common/log.dart';
export 'src/model/connect_error.dart';
export 'src/dfu/backend.dart';
export 'src/dfu/dfu_detector.dart';
export 'src/dfu/recovery_runner.dart';
export 'src/dfu/dfu_memory_layout.dart';
export 'src/dfu/dfuse_file.dart';
export 'src/dfu/stm32wb55/fus_state.dart';
export 'src/dfu/stm32wb55/option_bytes.dart';

import 'src/client/client.dart';

class FlipperOneClient {
  static final FlipperOneClient _singleton = FlipperOneClient._internal();

  FlipperClient? _client;

  FlipperOneClient._internal();

  factory FlipperOneClient() => _singleton;

  FlipperClient get() {
    _client ??= FlipperClient();
    return _client!;
  }

  FlipperClient call() => get();
}
