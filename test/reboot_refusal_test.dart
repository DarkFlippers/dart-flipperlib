import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a Flipper that refuses to reboot leaves behind.
///
/// `reboot` is fire-and-forget on purpose: a Flipper that obeys stops
/// answering mid-request, so awaiting the reply would mean waiting out the
/// five-second timeout on every *successful* reboot. The disconnect runs
/// either way.
///
/// That shape costs the caller any view of a refusal - firmware answers
/// ERROR_APP_SYSTEM_LOCKED while an app is running - and until qUnleashed#120
/// `.catchError((_) => <Main>[])` dropped it with nothing recorded anywhere.
/// The Device page went to disconnected while the Flipper sat there unchanged.
/// The warning below is the whole of what a consumer can see, so it is worth a
/// test.
class _RefusingClient extends FlipperClient {
  _RefusingClient(this.refusal);

  final Object refusal;
  bool disconnected = false;
  Main? sent;

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async {
    sent = request;
    throw refusal;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }
}

/// Accepts, the way a Flipper that is about to reboot does: the reply never
/// arrives and the request times out.
class _ObeyingClient extends FlipperClient {
  bool disconnected = false;

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) => Completer<List<Main>>().future;

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }
}

void main() {
  late List<(FlipperLogLevel, String)> lines;
  late FlipperLogSink? previousSink;
  late FlipperLogLevel previousLevel;

  setUp(() {
    lines = [];
    previousSink = Log.sink;
    previousLevel = Log.level;
    Log.sink = (level, message) => lines.add((level, message));
    Log.level = FlipperLogLevel.info;
  });

  tearDown(() {
    Log.sink = previousSink;
    Log.level = previousLevel;
  });

  final request = RebootRequest(mode: RebootRequest_RebootMode.OS);

  group('a Flipper that refuses to reboot', () {
    test('is reported at warning, not dropped', () async {
      final client = _RefusingClient(StateError('ERROR_APP_SYSTEM_LOCKED'));

      await client.reboot(request);

      expect(
        lines.where((l) => l.$1 == FlipperLogLevel.warning),
        isNotEmpty,
        reason: 'the only record that the device did not reboot',
      );
    });

    // The level is the behaviour a consumer routes on, and `info` is the one
    // it must not be: qUnleashed's own LogService drops info in release.
    test('says what the firmware answered', () async {
      final client = _RefusingClient(StateError('ERROR_APP_SYSTEM_LOCKED'));

      await client.reboot(request);

      expect(
        lines.single.$2,
        allOf(contains('reboot'), contains('ERROR_APP_SYSTEM_LOCKED')),
      );
    });

    // The refusal does not change the rest: this method's contract is that
    // the link goes, and a caller that stopped disconnecting on a refusal
    // would strand a session nobody can see.
    test('still lets the link go', () async {
      final client = _RefusingClient(StateError('ERROR_BUSY'));

      await client.reboot(request);

      expect(client.disconnected, isTrue);
    });

    test('still asks once', () async {
      final client = _RefusingClient(StateError('ERROR_BUSY'));

      await client.reboot(request);

      expect(client.sent?.hasSystemRebootRequest(), isTrue);
    });
  });

  group('a Flipper that obeys', () {
    // The success path never answers, so it must not wait for one - and it
    // must not log, or every reboot would carry a warning.
    test('is not waited for', () async {
      final client = _ObeyingClient();

      await client.reboot(request).timeout(const Duration(seconds: 2));

      expect(client.disconnected, isTrue);
    });

    test('leaves nothing in the log', () async {
      final client = _ObeyingClient();

      await client.reboot(request);

      expect(lines, isEmpty);
    });
  });
}
