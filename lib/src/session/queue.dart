import 'dart:async';

import '../common/log.dart';
import '../model/enums.dart';
import '../proto/generated/flipper.pb.dart';

// One outbound RPC frame waiting for its turn on the transport. Settles
// exactly once: markSent after the frame was handed to the transport, fail if
// it never made it out.
class QueuedRequest implements Comparable<QueuedRequest> {
  final Main frame;
  final FlipperRequestPriority priority;
  final int seq;
  final void Function()? onSent;
  final void Function(Object error)? onError;
  final bool interleavable;
  final bool holdsTxUntilAnswer;
  bool _settled = false;

  QueuedRequest({
    required this.frame,
    required this.priority,
    required this.seq,
    required this.holdsTxUntilAnswer,
    this.onSent,
    this.onError,
    this.interleavable = false,
  });

  void markSent() {
    if (_settled) return;
    _settled = true;
    onSent?.call();
  }

  void fail(Object error) {
    if (_settled) return;
    _settled = true;
    onError?.call(error);
  }

  String describe() {
    return 'cmdId=${frame.commandId} content=${frame.whichContent().name} '
        'priority=${priority.name} hasNext=${frame.hasNext}';
  }

  @override
  int compareTo(QueuedRequest other) {
    final byPriority = priority.index.compareTo(other.priority.index);
    if (byPriority != 0) return byPriority;
    return seq.compareTo(other.seq);
  }
}

// In-flight RPC call: collects response frames and owns the response watchdog
// timer. Completes exactly once.
class PendingRpc {
  final int commandId;
  final List<Main> frames = [];
  final Completer<List<Main>> _completer = Completer<List<Main>>();
  final Completer<void> _settled = Completer<void>();
  Timer? _timeoutTimer;
  Duration? _watchdogTimeout;
  void Function()? _watchdogCallback;
  int _frameCount = 0;

  // True once at least one frame of this command reached the transport. A
  // started command has state on the firmware side and cannot survive a link
  // drop; a never-started one replays safely on the next session.
  bool started = false;

  // When false, response frames are delivered through [onFrame] only and the
  // completed future carries an empty list — large transfers (storage reads)
  // would otherwise hold every protobuf frame in memory until completion.
  bool retainFrames = true;

  PendingRpc(this.commandId) {
    // Multi-frame requests may fail while their body is still being sent,
    // before the caller reaches `await future`; without this the error would
    // be reported as unhandled.
    unawaited(_completer.future.catchError((Object _) => <Main>[]));
  }

  void Function(Main frame)? onFrame;

  Future<List<Main>> get future => _completer.future;

  // Resolves when the call settles — success or failure — and never errors,
  // so the TX worker can wait for the response without try/catch.
  Future<void> get settled => _settled.future;

  int get frameCount => _frameCount;

  void add(Main frame) {
    _frameCount++;
    if (retainFrames) frames.add(frame);
    // A throwing user callback (e.g. a progress handler) must not abort RX
    // processing: the remaining frames of this chunk still have to be routed.
    try {
      onFrame?.call(frame);
    } catch (error) {
      Log.error('[RPC] onFrame callback threw for cmdId=$commandId: $error');
    }
  }

  // Arms (or re-arms with a new duration) the response watchdog. Callers mark
  // [started] separately, once the first frame actually reached the transport:
  // the watchdog also has to cover requests stuck in the queue before TX.
  void armTimeout(Duration timeout, void Function() onTimeout) {
    _watchdogTimeout = timeout;
    _watchdogCallback = onTimeout;
    _scheduleTimer();
  }

  void rearmTimeout() {
    if (_watchdogTimeout == null || _watchdogCallback == null) return;
    _scheduleTimer();
  }

  void _scheduleTimer() {
    _timeoutTimer?.cancel();
    final timeout = _watchdogTimeout;
    final cb = _watchdogCallback;
    if (timeout == null || cb == null) return;
    _timeoutTimer = Timer(timeout, () {
      if (_completer.isCompleted) return;
      cb();
    });
  }

  void cancelTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _watchdogTimeout = null;
    _watchdogCallback = null;
  }

  void complete() {
    cancelTimeout();
    if (_completer.isCompleted) return;
    _completer.complete(List.unmodifiable(frames));
    _settled.complete();
  }

  void completeError(Object error) {
    cancelTimeout();
    if (_completer.isCompleted) return;
    _completer.completeError(error);
    _settled.complete();
  }
}
