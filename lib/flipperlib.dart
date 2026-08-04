export 'protobuf.dart';
export 'flipper_client.dart';
export 'device/discovered.dart';
export 'log.dart';
export 'connect_error.dart';
export 'dfu/dfu_detector.dart';
export 'dfu/recovery_runner.dart';

import 'flipper_client.dart';

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
