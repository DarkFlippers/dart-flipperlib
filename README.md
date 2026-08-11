# flipperlib

[![source](https://img.shields.io/badge/source-GitHub-181717.svg?logo=github)](https://github.com/DarkFlippers/dart-flipperlib)
[![pub package](https://img.shields.io/pub/v/flipperlib.svg)](https://pub.dev/packages/flipperlib)
[![license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

Flipper Zero client for Flutter: BLE and USB links, the full protobuf RPC surface, CLI
passthrough and STM32WB55 recovery.

Built for [qUnleashed](https://github.com/DarkFlippers/qUnleashed), a Flipper Zero companion app.
Made by [ApertureFox Technology](https://github.com/apfxtech) at
[DarkFlippers](https://github.com/DarkFlippers).

## Features

- **Multi-session** — several links held at once, exactly one active. `activate()` reroutes
  every call and stream instantly; the other sessions stay connected and warm.
- **Transports** — BLE over GATT with flow control, USB serial with OS-level hotplug events.
- **RPC** — typed extensions per namespace: storage, app, gui, system, gpio, desktop, property,
  usb, ble. Chunked read/write with progress, request priorities, interleaving.
- **CLI** — switch to the text console and back, execute a command, stream raw bytes.
- **Recovery** — STM32WB55 DFU in a background isolate: firmware, wireless stack, option bytes.

## Platforms

|         | BLE | USB serial | DFU recovery |
| ------- | :-: | :--------: | :----------: |
| Android |  ✅ |     ✅     |      —       |
| iOS     |  ✅ |     —      |      —       |
| macOS   |  ✅ |     ✅     |      ✅      |
| Linux   |  ✅ |     ✅     |      ✅      |
| Windows |  ✅ |     ✅     |      ✅      |

Recovery needs libusb: bundled on macOS, `libusb-1.0` from the system on Linux and Windows.

## Install

```yaml
dependencies:
  flipperlib: ^1.0.0
```

## Usage

```dart
import 'package:flipperlib/flipperlib.dart';

final flipper = FlipperClient();
await flipper.initialize();                  // BLE permissions

final devices = await flipper.refreshDevices();
await flipper.connect(devices.first);        // RPC mode is entered for you

final listing = await flipper.storageList(ListRequest(path: '/ext'));
for (final response in listing.items) {
  for (final entry in response.file) {
    print(entry.name);
  }
}

await flipper.disconnect();
```

State arrives on broadcast streams — `devicesStream`, `connectionStream`, `sessionsStream`,
`messageStream`, `errorStream` — so the UI never polls.

## Logging

Off by default. Attach a sink to see anything; `trace` and `debug` are compiled out of release
builds.

```dart
Log.level = FlipperLogLevel.debug;
Log.sink = (level, message) => print('[$level] $message');
```

## See also

- [dartufbt](https://pub.dev/packages/dartufbt) — build `.fap` packages (Flipper Application
  Package): SDK deployment, ARM toolchain, compile and link. Desktop only. Build the `.fap`
  there, ship it with flipperlib.

## License

GPL-3.0. See [LICENSE](LICENSE).
