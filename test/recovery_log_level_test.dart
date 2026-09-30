import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which recovery lines a consumer has to keep, and which are commentary.
///
/// Recovery runs in a spawned isolate, so the consumer's logger is not
/// reachable from inside it: these messages are the only way a failure
/// crosses back. Every one of them used to arrive the same shape, so a
/// consumer that files them all as progress - which is what the app did -
/// dropped the wireless stack failing along with the rest. A recovery then
/// reported success over a Flipper whose BLE was broken. qUnleashed#119.
void main() {
  group('a line about what the run is doing', () {
    test('is progress without being asked', () {
      expect(
        const RecoveryLog('Waiting for the device').level,
        RecoveryLogLevel.progress,
      );
    });

    test('is what the default constructor still gives', () {
      expect(
        const RecoveryLog('Sending FW_UPGRADE command').message,
        'Sending FW_UPGRADE command',
      );
    });
  });

  group('a line about something that did not work', () {
    test('says so', () {
      expect(
        const RecoveryLog.warning('Radio flash failed').level,
        RecoveryLogLevel.warning,
      );
    });

    test('keeps its message', () {
      expect(
        const RecoveryLog.warning('Radio flash failed').message,
        'Radio flash failed',
      );
    });

    // The two are distinguishable, which is the whole point: a consumer
    // routes on the level rather than matching the text.
    test('is not the same as a progress line', () {
      expect(
        const RecoveryLog.warning('x').level,
        isNot(const RecoveryLog('x').level),
      );
    });
  });
}
