import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

/// [DeviceToken.fixed], and what a token is for.
///
/// Work outlives devices. A walk, an upload or a firmware transfer runs for as
/// long as it runs, and warm sessions let the user swap Flippers without the
/// link ever dropping - `isConnected` stays true right across the switch, so
/// it cannot be the test. A token is taken before the work and checked after
/// each await, before anything the switch invalidated is written down.
///
/// The real one is built from the client's own revision counter, and
/// `FlipperClient.deviceToken` is not nullable - so a fake client could not
/// answer it at all, and every caller of it was untestable from outside this
/// package. That is a virtual display left lit on the Flipper the user moved
/// away from, among others.
void main() {
  group('a token that is still current', () {
    const token = DeviceToken.fixed(current: true);

    test('says so', () {
      expect(token.isCurrent, isTrue);
    });

    test('is not stale', () {
      expect(token.isStale, isFalse);
    });
  });

  group('a token the switch has passed by', () {
    const token = DeviceToken.fixed(current: false);

    test('is stale', () {
      expect(token.isStale, isTrue);
    });

    test('is not current', () {
      expect(token.isCurrent, isFalse);
    });
  });

  group('two tokens', () {
    test('match when they say the same thing', () {
      expect(
        const DeviceToken.fixed(current: true),
        const DeviceToken.fixed(current: true),
      );
    });

    // A caller holds one and compares it later; two that disagree about the
    // device are not the same token whatever else they share.
    test('do not match when they disagree', () {
      expect(
        const DeviceToken.fixed(current: true),
        isNot(const DeviceToken.fixed(current: false)),
      );
    });

    test('hash together when they match', () {
      expect(
        const DeviceToken.fixed(current: true).hashCode,
        const DeviceToken.fixed(current: true).hashCode,
      );
    });

    test('keep their answer in a set', () {
      final held = <DeviceToken>{
        const DeviceToken.fixed(current: true),
        const DeviceToken.fixed(current: false),
      };

      expect(held, hasLength(2));
    });
  });
}
