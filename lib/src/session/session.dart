import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../client/client.dart';
import '../../protobuf.dart';
import '../common/log.dart';
import '../model/device.dart';
import '../model/enums.dart';
import '../model/exceptions.dart';
import '../transport/ble/ble.dart';
import '../transport/transport.dart';
import 'protocol.dart';
import 'queue.dart';

// One physical link to one device: transport, mode, request queue, RPC/CLI
// state, reconnect policy and the device-info cache all live here. The
// FlipperClient facade owns discovery and the session registry, pipes the
// active session's streams into its public ones and routes API calls to the
// active session. A non-active ("warm") session keeps its link and RPC state
// alive but receives no new requests.
enum LinkPhase { disconnected, connecting, connected }

class FlipperSession {
  FlipperSession(this._client, this.device);

  final FlipperClient _client;
  final FlipperDevice device;

  final connectionCtrl = StreamController<FlipperConnectionState>.broadcast();
  final modeCtrl = StreamController<FlipperMode>.broadcast();
  final rawCtrl = StreamController<List<int>>.broadcast();
  final textCtrl = StreamController<String>.broadcast();
  final messageCtrl = StreamController<Main>.broadcast();
  final broadcastCtrl = StreamController<Main>.broadcast();
  final errorCtrl = StreamController<FlipperRpcException>.broadcast();
  final deviceInfoCompleteCtrl =
      StreamController<Map<String, String>>.broadcast();
  final deviceInfoWatchCtrl = StreamController<Map<String, String>>.broadcast();
  final storageMutationCtrl = StreamController<void>.broadcast();

  final Map<int, PendingRpc> _pendingRpc = {};
  final List<QueuedRequest> _requestQueue = [];
  final Map<String, String> _deviceInfoCache = {};
  final Map<String, String> _deviceInfoWatchSnapshot = {};
  final _frameBuffer = FrameBuffer();
  final _utf8Decoder = const Utf8Decoder(allowMalformed: true);

  int _sessionGen = 0;
  Transport? transport;
  StreamSubscription<List<int>>? _transportSub;
  LinkPhase _linkPhase = LinkPhase.disconnected;
  bool _announcedConnecting = false;
  FlipperMode mode = FlipperMode.disconnected;
  Future<void>? _switchToRpcFuture;
  Future<void>? _deviceInfoFetch;
  bool cliExclusive = false;
  bool _autoRpc = true;
  bool deviceInfoFetched = false;
  int _rxParseErrorStreak = 0;
  Future<void> _cliChain = Future.value();
  int _storageOpsInFlight = 0;

  Completer<void>? _queueSignal;
  int? _workerGen;
  int _requestSeq = 0;
  QueuedRequest? _activeRequest;
  int? _txGroupCommandId;
  int _nextCommandId = 1;

  final Stopwatch _sessionUptime = Stopwatch();
  int _quickDropStreak = 0;
  int activationStamp = 0;

  bool get isConnected => _linkPhase == LinkPhase.connected;

  bool get isConnecting => _linkPhase == LinkPhase.connecting;

  bool get storageBusy => _storageOpsInFlight > 0;

  Map<String, String> get deviceInfoCache => Map.unmodifiable(_deviceInfoCache);

  Map<String, String> get deviceInfoWatchSnapshot =>
      Map.unmodifiable(_deviceInfoWatchSnapshot);

  String? getName() =>
      _deviceInfoCache['hardware_name'] ?? _deviceInfoCache['device_name'];

  void publishDeviceInfoPatch(Map<String, String> patch) {
    if (patch.isEmpty) return;
    _deviceInfoWatchSnapshot.addAll(patch);
    if (!deviceInfoWatchCtrl.isClosed) deviceInfoWatchCtrl.add(patch);
  }

  int nextCommandId() {
    do {
      _nextCommandId++;
      if (_nextCommandId > 0x7FFFFFFF) _nextCommandId = 1;
    } while (_nextCommandId == 0 || _pendingRpc.containsKey(_nextCommandId));
    return _nextCommandId;
  }

  void abortConnectInFlight() {
    if (_linkPhase != LinkPhase.connecting) return;
    if (device.isBle) {
      UniversalBleTransportBase.abortPendingConnect();
    }
  }

  // ── Link lifecycle ─────────────────────────────────────────────────────────

  // Opens a transport and commits the session. Runs on the client's lifecycle
  // chain; _reconnectLocked keeps the queue and the device-info cache alive
  // across re-establishment.
  Future<FlipperDevice> establishLocked({bool autoRpc = true}) async {
    _autoRpc = autoRpc;
    // A running scan competes with the connection for the radio. stopScan
    // returns once the platform scan is torn down; the settle then lets the
    // radio come free before the link is claimed.
    await _client.stopScan();
    await _client.awaitRadioSettled();

    final gen = ++_sessionGen;
    // Enter the `connecting` phase for the whole connect window. It returns to
    // `disconnected` on failure/supersession, or advances to `connected` the
    // moment the transport is committed (kept in lockstep with `transport`).
    _linkPhase = LinkPhase.connecting;
    _emitConnecting();
    Log.info(
      '[FlipperClient] connecting to ${device.name} '
      '(${device.link.name}:${device.id})',
    );
    Transport? transport;
    try {
      transport = await _client.openTransport(device);
      await transport.open();
    } catch (error) {
      _linkPhase = LinkPhase.disconnected;
      _clearConnecting();
      Log.error(
        '[FlipperClient] connect failed '
        'device=${device.name} link=${device.link.name}: $error',
      );
      await transport?.close();
      rethrow;
    }

    if (gen != _sessionGen) {
      _linkPhase = LinkPhase.disconnected;
      _clearConnecting();
      await transport.close();
      throw StateError('Connection attempt superseded');
    }

    this.transport = transport;
    _linkPhase = LinkPhase.connected;
    _announcedConnecting = false;
    _transportSub = transport.bytesStream.listen(
      _onTransportBytes,
      onError: (Object error, StackTrace stackTrace) {
        // Transports report failures via onTransportFault and never put error
        // events on bytesStream; defensive guard against a misbehaving
        // backend.
        Log.error('[FlipperClient] transport stream error: $error');
        _scheduleFaultRecovery(gen, error);
      },
      onDone: () => _onTransportClosed(transport!),
    );

    _setMode(transport.initialMode);
    _startWorker(gen);
    _sessionUptime
      ..reset()
      ..start();
    Log.info('[FlipperClient] connected to ${device.name}');
    if (autoRpc && transport.supportsCli) {
      unawaited(
        switchToRpcMode().catchError((Object error) {
          Log.error('[FlipperClient] automatic RPC switch failed: $error');
        }),
      );
    }
    return device;
  }

  // The single teardown path for every way a session ends. Detaches all
  // session state synchronously before the first await, so late transport
  // callbacks always see a consistent disconnected picture. Registry removal
  // is the caller's decision — a CLI mode switch tears down and re-establishes
  // the same session.
  Future<void> teardownLocked(Object reason) async {
    _sessionGen++;
    final transport = this.transport;
    if (transport == null &&
        _linkPhase == LinkPhase.disconnected &&
        mode == FlipperMode.disconnected &&
        _requestQueue.isEmpty &&
        _pendingRpc.isEmpty &&
        _deviceInfoCache.isEmpty &&
        _deviceInfoWatchSnapshot.isEmpty) {
      return;
    }
    _sessionUptime
      ..stop()
      ..reset();
    _quickDropStreak = 0;

    final sub = _transportSub;
    this.transport = null;
    _linkPhase = LinkPhase.disconnected;
    _transportSub = null;
    _announcedConnecting = false;
    _switchToRpcFuture = null;
    _deviceInfoFetch = null;
    _deviceInfoCache.clear();
    _deviceInfoWatchSnapshot.clear();
    deviceInfoFetched = false;
    _frameBuffer.clear();
    _rxParseErrorStreak = 0;

    final requestError = reason is Exception
        ? reason
        : StateError('Disconnected: $reason');
    _failAllRequests(requestError);
    _setMode(FlipperMode.disconnected, closeReason: reason);
    _signalWorker();

    if (sub != null) await sub.cancel();
    if (transport != null) await transport.close();
  }

  // Recovery for faults reported by callbacks. Bound to the generation that
  // faulted: by the time the chain reaches it, a newer session may already be
  // up and must not be touched. Reconnects in place when allowed, otherwise
  // tears down with the original reason and retires the session.
  void _scheduleFaultRecovery(int gen, Object reason) {
    // Freeze the uptime now: the recovery op runs later through the chain and
    // must judge the dead session by its actual lifetime, not by how long the
    // recovery sat in the queue.
    if (gen == _sessionGen) _sessionUptime.stop();
    unawaited(
      _client.serialized(() async {
        if (gen != _sessionGen) return;
        if (!_client.autoReconnect || !_mayAutoReconnect()) {
          await teardownLocked(reason);
          _client.onSessionEnded(this);
          return;
        }
        await _reconnectLocked(reason);
      }),
    );
  }

  bool _mayAutoReconnect() {
    // The stopwatch is already stopped at fault time, so isRunning must not
    // gate the healthy-session check.
    if (_sessionUptime.elapsed >= FlipperClient.quickDropWindow) {
      _quickDropStreak = 0;
    }
    if (_quickDropStreak >= FlipperClient.maxQuickDropStreak) {
      // Two short-lived sessions in a row: the environment or device is not
      // ready, stop interfering until the user reconnects manually.
      _quickDropStreak = 0;
      return false;
    }
    _quickDropStreak++;
    return true;
  }

  // In-place reconnect to the same device. Keeps the device identity, the
  // device-info cache and every queued request that never started
  // transmitting; fails only commands whose firmware-side state died with the
  // link. Exactly one connect attempt — on failure the session ends with the
  // original fault reason.
  Future<void> _reconnectLocked(Object reason) async {
    Log.info(
      '[FlipperClient] link lost: $reason; reconnecting to ${device.name}',
    );
    _sessionGen++;

    final transport = this.transport;
    final sub = _transportSub;
    this.transport = null;
    // The link is down and about to be re-established; establishLocked
    // re-affirms `connecting` and advances to `connected` on success.
    _linkPhase = LinkPhase.connecting;
    _transportSub = null;
    _switchToRpcFuture = null;
    _frameBuffer.clear();
    _rxParseErrorStreak = 0;

    _failStartedRequests(
      reason is Exception ? reason : StateError('Disconnected: $reason'),
    );
    _setMode(FlipperMode.disconnected, closeReason: reason, reconnecting: true);
    _signalWorker();

    if (sub != null) await sub.cancel();
    if (transport != null) await transport.close();

    // Settle before re-opening. After a fault the transport is already closed,
    // so close() returns without waiting for the platform disconnect to
    // confirm; re-connecting in the same instant leaves CoreBluetooth still
    // tearing down the old CBPeripheral, which wedges the new attempt (lost
    // write callbacks, then a 20s connect timeout). A brief pause lets the
    // platform release the old link first.
    final settleGen = _sessionGen;
    await Future<void>.delayed(FlipperClient.reconnectSettle);
    if (settleGen != _sessionGen) return;

    try {
      await establishLocked(autoRpc: _autoRpc);
    } catch (error) {
      Log.error('[FlipperClient] reconnect failed: $error');
      await teardownLocked(reason);
      // The mode is already `disconnected`, so _setMode stayed silent; emit
      // the final (non-reconnecting) state explicitly so listeners leave the
      // "reconnecting" presentation.
      if (!connectionCtrl.isClosed) {
        connectionCtrl.add(
          FlipperConnectionState(
            mode: FlipperMode.disconnected,
            device: null,
            connected: false,
            closeReason: reason,
          ),
        );
      }
      _client.onSessionEnded(this);
      return;
    }
    Log.info('[FlipperClient] reconnected to ${device.name}');
  }

  // Fails commands that already (partially) reached the wire — their
  // firmware-side state died with the link. Requests still waiting in the
  // queue replay transparently on the restored session.
  void _failStartedRequests(Object error) {
    _activeRequest = null;
    final startedIds = <int>[
      for (final entry in _pendingRpc.entries)
        if (entry.value.started) entry.key,
    ];
    for (final id in startedIds) {
      _failPendingById(id, error);
    }
  }

  void _failAllRequests(Object error) {
    _txGroupCommandId = null;
    _activeRequest = null;
    final queued = List<QueuedRequest>.from(_requestQueue);
    _requestQueue.clear();
    for (final request in queued) {
      request.fail(error);
    }
    final pending = List<PendingRpc>.from(_pendingRpc.values);
    _pendingRpc.clear();
    for (final p in pending) {
      p.completeError(error);
    }
  }

  void _onTransportClosed(Transport transport) {
    if (!identical(transport, transport)) return;
    final reason = transport.closeReason ?? 'transport closed';
    final active = _activeRequest;
    final detailedReason = active == null
        ? reason
        : FlipperTransportError('$reason; active ${active.describe()}');
    Log.error('[FlipperClient] transport closed: $detailedReason');
    _scheduleFaultRecovery(_sessionGen, detailedReason);
  }

  // ── Mode switching / CLI ───────────────────────────────────────────────────

  Future<void> switchToRpcMode() {
    if (cliExclusive) {
      return Future.error(
        StateError('RPC switch blocked: CLI session is active'),
      );
    }
    if (mode == FlipperMode.rpc) return Future.value();
    return _switchToRpcFuture ??= _doSwitchToRpcMode().whenComplete(() {
      _switchToRpcFuture = null;
    });
  }

  Future<void> _doSwitchToRpcMode() async {
    // Strict on purpose: a real RPC sender (callRpcFrames / sendRpc switches
    // here) must fail fast when there is no transport instead of enqueuing a
    // request that can only time out. The lenient "already disconnected"
    // handling lives in FlipperClient.enterRpcMode(), the mode-restore entry
    // point.
    final transport = _requireTransport();
    if (mode == FlipperMode.rpc) return;
    if (!transport.supportsCli) {
      if (identical(transport, transport)) {
        _setMode(FlipperMode.rpc);
        _signalWorker();
      }
      return;
    }

    final promptSeen = await _waitForTextMarker(
      FlipperClient.cliPrompt,
      timeout: const Duration(seconds: 5),
      trigger: transport.nudgeCli,
    );
    Log.info(
      promptSeen != null
          ? '[RPC] CLI prompt detected'
          : '[RPC] CLI prompt not seen within 5s, continuing',
    );
    if (!identical(transport, transport)) return;

    final echoed = await _waitForTextMarker(
      'start_rpc_session',
      timeout: const Duration(seconds: 2),
      trigger: () => transport.writeAscii(FlipperClient.startRpcSession),
    );
    Log.info(
      echoed != null
          ? '[RPC] start_rpc_session echo received'
          : '[RPC] start_rpc_session echo not seen, may already be in RPC mode',
    );

    // Let trailing CLI bytes drain before treating the stream as protobuf.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!identical(transport, transport)) return;
    _frameBuffer.clear();
    _setMode(FlipperMode.rpc);
    _signalWorker();
    Log.info('[RPC] RPC mode active');
  }

  Future<void> switchToCliMode() => _client.serialized(_switchToCliLocked);

  Future<void> _switchToCliLocked() async {
    if (!isConnected) {
      throw StateError('No device connected');
    }
    final transport = _requireTransport();
    if (!transport.supportsCli) {
      throw FlipperUnsupportedModeError(
        'CLI mode is not available on this transport',
      );
    }
    if (mode == FlipperMode.cli) return;

    // The firmware offers no RPC->CLI switch; the session is recreated.
    // autoRpc is off so the automatic RPC switch cannot race the CLI prompt.
    await teardownLocked('switching to CLI mode');
    try {
      await establishLocked(autoRpc: false);
    } catch (error) {
      _client.onSessionEnded(this);
      rethrow;
    }
    await _ensureCliPrompt();
  }

  // Serialized through _cliChain: concurrent calls would interleave their
  // writes on the shared text stream and corrupt each other's output.
  Future<String> executeCli(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final result = _cliChain.then(
      (_) => _executeCliInner(command, timeout: timeout),
    );
    _cliChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _executeCliInner(
    String command, {
    required Duration timeout,
  }) async {
    if (!_requireTransport().supportsCli) {
      throw FlipperUnsupportedModeError(
        'CLI commands are not available on this transport',
      );
    }
    if (mode != FlipperMode.cli) {
      await switchToCliMode();
    }
    final transport = _requireTransport();
    final text = await _waitForTextMarker(
      FlipperClient.cliPrompt,
      timeout: timeout,
      trigger: () async {
        await transport.writeAscii('\r');
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await transport.writeAscii('$command\r');
      },
    );
    if (text == null) {
      throw TimeoutException('CLI command timeout: $command');
    }
    return _trimCliResult(text, command);
  }

  Future<void> writeCliText(String text) async {
    final transport = _requireTransport();
    if (!transport.supportsCli) {
      throw FlipperUnsupportedModeError(
        'CLI mode is not available on this transport',
      );
    }
    if (mode == FlipperMode.rpc) {
      throw StateError('Cannot send CLI text while in RPC mode');
    }
    await transport.writeAscii(text);
  }

  Future<void> writeCliBytes(Uint8List bytes) async {
    final transport = _requireTransport();
    if (!transport.supportsCli) {
      throw FlipperUnsupportedModeError(
        'CLI mode is not available on this transport',
      );
    }
    if (mode == FlipperMode.rpc) {
      throw StateError('Cannot send CLI bytes while in RPC mode');
    }
    await transport.write(bytes);
  }

  Future<void> _ensureCliPrompt() async {
    final transport = _requireTransport();
    final seen = await _waitForTextMarker(
      FlipperClient.cliPrompt,
      timeout: const Duration(seconds: 5),
      trigger: transport.nudgeCli,
    );
    if (seen == null) {
      throw TimeoutException('CLI prompt timeout');
    }
  }

  // Listens on the session's text stream until [marker] appears in the
  // accumulated text or [timeout] elapses. Returns the full accumulated text
  // on match, null on timeout — a timeout is a result, not an exception.
  // [trigger] runs after the listener is attached; its write errors surface as
  // a non-match.
  //
  // The marker is searched in a rolling tail window (last chunk plus
  // marker-1 carry-over chars), so cost stays O(chunk) per event instead of
  // re-scanning the whole accumulated text — large CLI outputs used to make
  // this quadratic.
  Future<String?> _waitForTextMarker(
    String marker, {
    required Duration timeout,
    Future<void> Function()? trigger,
  }) async {
    final matched = Completer<String?>();
    final chunks = StringBuffer();
    final carry = marker.length - 1;
    var window = '';

    final sub = textCtrl.stream.listen((chunk) {
      if (matched.isCompleted) return;
      chunks.write(chunk);
      window = window + chunk;
      if (window.contains(marker)) {
        matched.complete(chunks.toString());
        return;
      }
      if (window.length > carry) {
        window = window.substring(window.length - carry);
      }
    });
    final timer = Timer(timeout, () {
      if (!matched.isCompleted) matched.complete(null);
    });

    if (trigger != null) {
      unawaited(
        trigger().catchError((Object error) {
          Log.error('[CLI] trigger write failed: $error');
        }),
      );
    }

    final result = await matched.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  // ── RPC senders ────────────────────────────────────────────────────────────

  Future<void> sendRpc(
    Main message, {
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
    Duration sendTimeout = const Duration(seconds: 30),
  }) async {
    if (mode != FlipperMode.rpc) {
      await switchToRpcMode();
    }
    if (message.commandId == 0) {
      message.commandId = nextCommandId();
    }
    final sent = Completer<void>();
    final queued = QueuedRequest(
      frame: message,
      priority: priority,
      seq: _requestSeq++,
      holdsTxUntilAnswer: false,
      onSent: () {
        if (!sent.isCompleted) sent.complete();
      },
      onError: (error) {
        if (!sent.isCompleted) sent.completeError(error);
      },
    );
    _enqueueRequest(queued);
    // A hung transport write must surface as an error, not an infinite await.
    final timer = Timer(sendTimeout, () {
      if (sent.isCompleted) return;
      _requestQueue.remove(queued);
      queued.fail(
        TimeoutException(
          'RPC send timeout after ${sendTimeout.inSeconds}s '
          'for ${queued.describe()}',
        ),
      );
    });
    try {
      await sent.future;
    } finally {
      timer.cancel();
    }
  }

  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async {
    if (mode != FlipperMode.rpc) {
      await switchToRpcMode();
    }
    final commandId = request.commandId == 0
        ? nextCommandId()
        : request.commandId;
    request.commandId = commandId;

    final pending = PendingRpc(commandId)
      ..onFrame = onFrame
      ..retainFrames = retainFrames;
    _pendingRpc[commandId] = pending;

    _enqueueRequest(
      QueuedRequest(
        frame: request,
        priority: priority,
        seq: _requestSeq++,
        interleavable: interleavable,
        holdsTxUntilAnswer: !pipelined,
        onSent: () {
          pending.started = true;
          pending.rearmTimeout();
          if (onSent == null) return;
          try {
            onSent();
          } catch (error) {
            Log.error(
              '[RPC] onSent callback threw for cmdId=$commandId: $error',
            );
          }
        },
        onError: (error) => _failPendingById(commandId, error),
      ),
    );
    // Armed at enqueue, not at TX: a write that never completes (hung
    // platform stack) must not leave the caller waiting forever.
    pending.armTimeout(timeout, () {
      _onRpcTimeout(
        commandId,
        'RPC timeout for commandId=$commandId '
        'after ${timeout.inSeconds}s started=${pending.started} '
        'framesReceived=${pending.frameCount}',
      );
    });

    final content = request.whichContent();
    final trackStorage = FlipperClient.heavyStorageContent.contains(content);
    if (trackStorage) _storageOpsInFlight++;
    try {
      return await pending.future;
    } finally {
      _pendingRpc.remove(commandId);
      _releaseTxGroup(commandId);
      pending.cancelTimeout();
      if (trackStorage) {
        _storageOpsInFlight--;
        _notifyStorageMutation(content);
      }
    }
  }

  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) body, {
    Duration timeout = const Duration(seconds: 60),
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
  }) async {
    if (mode != FlipperMode.rpc) {
      await switchToRpcMode();
    }
    final commandId = nextCommandId();
    final pending = PendingRpc(commandId);
    _pendingRpc[commandId] = pending;
    var finalFrameSent = false;
    var timeoutArmed = false;
    // The command's content becomes known with the first frame the body
    // sends; storage tracking starts there and ends with the call.
    var trackedContent = Main_Content.notSet;
    var trackingStorage = false;

    void armOrRearmTimeout() {
      if (timeoutArmed) {
        pending.rearmTimeout();
        return;
      }
      timeoutArmed = true;
      pending.armTimeout(timeout, () {
        _onRpcTimeout(
          commandId,
          'Multi-frame RPC timeout waiting for ACK commandId=$commandId '
          'after ${timeout.inSeconds}s finalFrameSent=$finalFrameSent '
          'started=${pending.started} '
          'queued=${_requestQueue.length} pending=${_pendingRpc.keys.toList()}',
        );
      });
    }

    Future<void> sendFrame(Main frame) {
      frame.commandId = commandId;
      if (trackedContent == Main_Content.notSet) {
        trackedContent = frame.whichContent();
        if (FlipperClient.heavyStorageContent.contains(trackedContent)) {
          trackingStorage = true;
          _storageOpsInFlight++;
        }
      }
      final sent = Completer<void>();
      final isFinal = !frame.hasNext;
      _enqueueRequest(
        QueuedRequest(
          frame: frame,
          priority: priority,
          seq: _requestSeq++,
          holdsTxUntilAnswer: true,
          onSent: () {
            if (isFinal) finalFrameSent = true;
            pending.started = true;
            armOrRearmTimeout();
            if (!sent.isCompleted) sent.complete();
          },
          onError: (error) {
            if (!sent.isCompleted) sent.completeError(error);
          },
        ),
      );
      // Armed at enqueue (see callRpcFrames): a frame stuck before TX must
      // still time out instead of hanging the upload body forever.
      armOrRearmTimeout();
      return sent.future;
    }

    try {
      try {
        await body(sendFrame);
      } catch (e) {
        _failPendingById(commandId, e);
        rethrow;
      }

      if (!finalFrameSent) {
        final err = StateError(
          'Multi-frame body completed without sending a final frame '
          '(hasNext=false) for commandId=$commandId',
        );
        _failPendingById(commandId, err);
        throw err;
      }

      return await pending.future;
    } finally {
      _pendingRpc.remove(commandId);
      _releaseTxGroup(commandId);
      pending.cancelTimeout();
      if (trackingStorage) {
        _storageOpsInFlight--;
        _notifyStorageMutation(trackedContent);
      }
    }
  }

  void _notifyStorageMutation(Main_Content content) {
    if (!FlipperClient.mutatingStorageContent.contains(content)) return;
    if (storageMutationCtrl.isClosed) return;
    storageMutationCtrl.add(null);
  }

  void _onRpcTimeout(int commandId, String message) {
    final active = _activeRequest;
    final detailed = active == null
        ? message
        : '$message; active ${active.describe()}';
    Log.error('[RPC] timeout: $detailed');
    final pending = _pendingRpc.remove(commandId);
    _removeQueuedCommand(commandId, 'timeout before TX');
    _releaseTxGroup(commandId);
    pending?.completeError(TimeoutException(detailed));
  }

  void _failPendingById(int commandId, Object error) {
    final pending = _pendingRpc.remove(commandId);
    _removeQueuedCommand(commandId, 'request failed');
    _releaseTxGroup(commandId);
    pending?.completeError(error);
  }

  void _releaseTxGroup(int commandId) {
    if (_txGroupCommandId != commandId) return;
    _txGroupCommandId = null;
    _signalWorker();
  }

  // Removed requests are failed, never dropped silently: a multi-frame body
  // awaiting sendFrame() must observe the failure instead of hanging.
  void _removeQueuedCommand(int commandId, String reason) {
    final removed = <QueuedRequest>[];
    _requestQueue.removeWhere((r) {
      if (r.frame.commandId != commandId) return false;
      removed.add(r);
      return true;
    });
    if (removed.isEmpty) return;
    Log.info(
      '[RPC] dropped ${removed.length} queued frame(s) '
      'for cmdId=$commandId: $reason',
    );
    for (final request in removed) {
      request.fail(StateError('Request dropped: $reason'));
    }
  }

  void _enqueueRequest(QueuedRequest request) {
    var inserted = false;
    for (var i = 0; i < _requestQueue.length; i++) {
      if (request.compareTo(_requestQueue[i]) < 0) {
        _requestQueue.insert(i, request);
        inserted = true;
        break;
      }
    }
    if (!inserted) {
      _requestQueue.add(request);
    }
    _signalWorker();
  }

  void _signalWorker() {
    final signal = _queueSignal;
    _queueSignal = null;
    fireOnce(signal);
  }

  void _startWorker(int gen) {
    if (_workerGen == gen) return;
    _workerGen = gen;
    unawaited(_runWorker(gen));
  }

  QueuedRequest? _peekNext() {
    if (_requestQueue.isEmpty) return null;
    final lockedId = _txGroupCommandId;
    if (lockedId != null) {
      final idx = _requestQueue.indexWhere(
        (r) => r.frame.commandId == lockedId || r.interleavable,
      );
      if (idx < 0) return null;
      return _requestQueue[idx];
    }
    return _requestQueue.first;
  }

  QueuedRequest? _dequeueNext() {
    final request = _peekNext();
    if (request != null) _requestQueue.remove(request);
    return request;
  }

  bool _isBatchable(QueuedRequest request) =>
      !request.frame.hasNext && !request.holdsTxUntilAnswer;

  bool _hasDispatchableRequest() {
    if (_requestQueue.isEmpty) return false;
    final lockedId = _txGroupCommandId;
    if (lockedId == null) return true;
    return _requestQueue.any(
      (r) => r.frame.commandId == lockedId || r.interleavable,
    );
  }

  // The only writer in RPC mode. Commands are pipelined by default: the worker
  // hands a frame to the transport and moves on, so several commands are in
  // flight at once and the firmware answers each by commandId. The firmware's
  // 1024-byte input buffer is protected by the transport's flow-control credit,
  // not by waiting here. A caller that must not overlap with the next command
  // (pipelined: false) still parks the worker on its answer, and multi-frame
  // commands keep the TX group locked until their final frame.
  Future<void> _runWorker(int gen) async {
    while (gen == _sessionGen) {
      final transport = this.transport;
      if (transport == null) break;

      QueuedRequest? request;
      if (mode == FlipperMode.rpc) {
        request = _dequeueNext();
      }
      if (request == null) {
        final signal = _queueSignal ??= Completer<void>();
        if (mode == FlipperMode.rpc && _hasDispatchableRequest()) {
          // A request slipped in between dequeue and signal registration.
          continue;
        }
        await signal.future;
        continue;
      }

      final frame = request.frame;
      final batch = <QueuedRequest>[request];
      final builder = BytesBuilder(copy: false)..add(RpcProtocol.encode(frame));
      final batchLimit = transport.maxWriteBatchSize;
      if (_isBatchable(request)) {
        while (builder.length < batchLimit) {
          final next = _peekNext();
          if (next == null || !_isBatchable(next)) break;
          final nextEncoded = RpcProtocol.encode(next.frame);
          if (builder.length + nextEncoded.length > batchLimit) break;
          _requestQueue.remove(next);
          builder.add(nextEncoded);
          batch.add(next);
        }
      }
      final encoded = builder.takeBytes();
      _activeRequest = request;

      Object? writeError;
      try {
        await transport.write(encoded);
      } catch (error) {
        writeError = error;
      }
      if (gen != _sessionGen) {
        // Session ended while writing; teardown already failed the pending
        // state, settle the queue entries.
        for (final queued in batch) {
          queued.fail(writeError ?? StateError('Disconnected'));
        }
        break;
      }
      if (writeError != null) {
        Log.error('[RPC] tx failed ${request.describe()}: $writeError');
        _activeRequest = null;
        _releaseTxGroup(frame.commandId);
        for (final queued in batch) {
          queued.fail(
            FlipperTransportError(
              'RPC write failed for ${queued.describe()}: $writeError',
            ),
          );
        }
        // A dead transport announces itself through its done event, which
        // schedules the teardown.
        continue;
      }
      if (Log.debugOn) {
        Log.debug(
          '[RPC] tx ok ${request.describe()} bytes=${encoded.length}'
          '${batch.length > 1 ? ' batched=${batch.length}' : ''}',
        );
      }

      if (frame.commandId != 0 && frame.hasNext) {
        _txGroupCommandId = frame.commandId;
      }
      for (final queued in batch) {
        queued.markSent();
      }

      for (final queued in batch) {
        final queuedFrame = queued.frame;
        if (queuedFrame.commandId == 0 || queuedFrame.hasNext) continue;
        _releaseTxGroup(queuedFrame.commandId);
        if (!queued.holdsTxUntilAnswer) continue;
        final pending = _pendingRpc[queuedFrame.commandId];
        if (pending != null) {
          // Settles on response, timeout or teardown — never hangs.
          await pending.settled;
        }
      }
      if (identical(_activeRequest, request)) _activeRequest = null;
    }

    if (_workerGen == gen) {
      _workerGen = null;
    }
  }

  // ── RX path ────────────────────────────────────────────────────────────────

  void _onTransportBytes(List<int> chunk) {
    rawCtrl.add(chunk);

    if (mode == FlipperMode.rpc) {
      final result = _frameBuffer.push(chunk, onParseError: _onFrameParseError);
      if (result.frames.isEmpty) {
        if (Log.debugOn) {
          Log.debug(
            '[RPC] rx ${chunk.length} bytes buffered '
            '(${result.pendingState ?? 'no pending frame'})',
          );
        }
        return;
      }
      for (final frame in result.frames) {
        // A throwing listener (messageStream subscriber, select() transform)
        // must not abort the loop: the remaining frames of this chunk would
        // be lost and their commands would time out.
        try {
          _routeFrame(frame);
        } catch (error) {
          Log.error('[RPC] frame routing threw: $error');
        }
      }
      if (Log.debugOn && result.pendingState != null) {
        Log.debug(
          '[RPC] parsed ${result.frames.length} frame(s), residual '
          '${result.pendingState}',
        );
      }
      return;
    }

    final text = _utf8Decoder.convert(chunk);
    if (Log.debugOn) {
      Log.debug(
        '[CLI] rx: ${text.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}',
      );
    }
    textCtrl.add(text);
  }

  void _routeFrame(Main frame) {
    // Random bytes occasionally survive Main.fromBuffer (protobuf tolerates
    // unknown fields), so a parsed frame alone does not prove the stream is
    // healthy — a desynchronized session could otherwise alternate between
    // parse errors and accidental "successes" forever. Only frames that match
    // an in-flight command or carry recognizable content reset the streak.
    if (frame.whichContent() != Main_Content.notSet ||
        _pendingRpc.containsKey(frame.commandId)) {
      _rxParseErrorStreak = 0;
    }
    messageCtrl.add(frame);

    if (frame.hasSystemDeviceInfoResponse()) {
      final info = frame.systemDeviceInfoResponse;
      final key = info.key.trim();
      final value = info.value.trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        _deviceInfoCache[key] = value;
        publishDeviceInfoPatch({key: value});
      }
    }

    final commandId = frame.commandId;
    if (commandId == 0) {
      if (Log.debugOn) {
        // Broadcasts arrive at screen-streaming frame rate; keep this cheap.
        Log.debug('[RPC] rx broadcast content=${frame.whichContent().name}');
      }
      final error = exceptionFromResponse(frame);
      if (error != null && !errorCtrl.isClosed) {
        errorCtrl.add(error);
      }
      if (frame.commandStatus == CommandStatus.ERROR_DECODE) {
        // The firmware lost protobuf framing on its RX side; it closes the
        // RPC session right after sending this (and restarts its BLE stack).
        Log.error('[RPC] firmware reported ERROR_DECODE; session is dead');
        _scheduleFaultRecovery(
          _sessionGen,
          FlipperTransportError(
            'Firmware reported a protobuf decode error and closed the '
            'RPC session',
          ),
        );
        return;
      }
      broadcastCtrl.add(frame);
      return;
    }

    final pending = _pendingRpc[commandId];
    if (pending == null) {
      if (frame.commandStatus ==
          CommandStatus.ERROR_CONTINUOUS_COMMAND_INTERRUPTED) {
        // Expected aftermath of a timed-out multi-frame command: the firmware
        // closes the abandoned write stream when the next command arrives and
        // reports it against the old (already failed) commandId.
        Log.info(
          '[RPC] firmware closed interrupted stream cmdId=$commandId '
          '(command already timed out locally)',
        );
        return;
      }
      Log.error('[RPC] rx unmatched frame cmdId=$commandId');
      return;
    }

    if (Log.debugOn) {
      Log.debug(
        '[RPC] rx frame cmdId=$commandId hasNext=${frame.hasNext} '
        'status=${frame.commandStatus.name} '
        'content=${frame.whichContent().name} '
        'frameN=${pending.frameCount + 1}',
      );
    }
    pending.add(frame);

    if (frame.hasNext) {
      pending.rearmTimeout();
      return;
    }

    _pendingRpc.remove(commandId);
    _releaseTxGroup(commandId);
    final error = exceptionFromResponse(frame);
    if (error != null) {
      if (!errorCtrl.isClosed) errorCtrl.add(error);
      pending.completeError(error);
    } else {
      pending.complete();
    }
  }

  void _onFrameParseError(Object error) {
    _rxParseErrorStreak++;
    Log.error(
      '[RPC] rx parse error '
      '($_rxParseErrorStreak/${FlipperClient.maxRxParseErrorStreak}): '
      '$error',
    );
    if (_rxParseErrorStreak < FlipperClient.maxRxParseErrorStreak) return;
    // The inbound stream is desynchronized beyond recovery; close the session
    // with the real reason. Poking the firmware's reset characteristic would
    // restart its whole BLE stack, turning one bad frame into a link drop.
    _scheduleFaultRecovery(
      _sessionGen,
      FlipperTransportError('RPC byte stream desynchronized: $error'),
    );
  }

  // ── Device info ────────────────────────────────────────────────────────────

  Future<String> awaitName() async {
    final cached = getName();
    if (cached != null && cached.isNotEmpty) return cached;

    // Resolves as soon as the name arrives mid-fetch; a failed fetch surfaces
    // its error instead of leaving the caller waiting on a stream that will
    // never emit.
    final fetch = _ensureDeviceInfoFetch();
    final nameArrived = Completer<void>();
    final sub = deviceInfoWatchCtrl.stream.listen((patch) {
      final hasName =
          (patch['hardware_name']?.isNotEmpty ?? false) ||
          (patch['device_name']?.isNotEmpty ?? false);
      if (hasName && !nameArrived.isCompleted) nameArrived.complete();
    });
    try {
      await Future.any([nameArrived.future, fetch]);
    } finally {
      await sub.cancel();
    }

    final name = getName();
    if (name == null || name.isEmpty) {
      throw StateError('Device info does not contain a device name');
    }
    return name;
  }

  Future<Map<String, String>> awaitDeviceInfo() async {
    if (deviceInfoFetched) return deviceInfoCache;
    await _ensureDeviceInfoFetch();
    return deviceInfoCache;
  }

  // Device info is fetched on demand (awaitName / awaitDeviceInfo), through
  // the normal request queue, at most once per session. The library starts no
  // RPC traffic on its own at connect time. The returned future errors when
  // the fetch fails (no transport, RPC error, link drop) so callers fail fast
  // instead of waiting for a snapshot that will never arrive; a later call
  // starts a fresh attempt.
  Future<void> _ensureDeviceInfoFetch() {
    final existing = _deviceInfoFetch;
    if (existing != null) return existing;
    if (deviceInfoFetched) return Future.value();
    if (transport == null) {
      return Future.error(
        StateError('Cannot fetch device info: no active transport'),
      );
    }
    late final Future<void> fetch;
    fetch = _fetchDeviceInfoOnce().whenComplete(() {
      if (identical(_deviceInfoFetch, fetch)) _deviceInfoFetch = null;
    });
    _deviceInfoFetch = fetch;
    return fetch;
  }

  Future<void> _fetchDeviceInfoOnce() async {
    // Session generation, not connectedness: the cache stays valid across an
    // automatic reconnect (generation bumps but the fetch retries later), but
    // never survives a teardown.
    final gen = _sessionGen;
    try {
      await callRpcFrames(
        Main(systemDeviceInfoRequest: DeviceInfoRequest()),
        priority: FlipperRequestPriority.foreground,
        retainFrames: false,
      );
    } catch (error) {
      Log.error('[FlipperClient] device info fetch failed: $error');
      rethrow;
    }
    if (gen != _sessionGen) {
      throw StateError('Device info fetch outlived its session');
    }
    deviceInfoFetched = true;
    final snapshot = deviceInfoCache;
    publishDeviceInfoPatch(snapshot);
    if (!deviceInfoCompleteCtrl.isClosed) {
      deviceInfoCompleteCtrl.add(snapshot);
    }
  }

  // ── Events ─────────────────────────────────────────────────────────────────

  // Emits the in-flight connect as a connection event. Goes straight to the
  // controller rather than through _setMode: the mode stays `disconnected`
  // until the transport commits, so there is no mode transition to ride on.
  void _emitConnecting() {
    _announcedConnecting = true;
    if (connectionCtrl.isClosed) return;
    connectionCtrl.add(
      FlipperConnectionState(
        mode: mode,
        device: device,
        connected: false,
        connecting: true,
      ),
    );
  }

  // Clears the in-flight attempt and announces the terminal disconnect, which
  // _setMode would swallow because the mode never left `disconnected`.
  void _clearConnecting() {
    if (!_announcedConnecting) return;
    _announcedConnecting = false;
    if (connectionCtrl.isClosed) return;
    connectionCtrl.add(
      FlipperConnectionState(mode: mode, device: null, connected: false),
    );
  }

  void _setMode(
    FlipperMode mode, {
    Object? closeReason,
    bool reconnecting = false,
  }) {
    if (this.mode == mode) return;
    this.mode = mode;
    if (!modeCtrl.isClosed) modeCtrl.add(mode);
    if (connectionCtrl.isClosed) return;
    connectionCtrl.add(
      FlipperConnectionState(
        mode: mode,
        device: mode != FlipperMode.disconnected || reconnecting
            ? device
            : null,
        connected: mode != FlipperMode.disconnected,
        closeReason: closeReason,
        reconnecting: reconnecting,
      ),
    );
  }

  Transport _requireTransport() {
    final transport = this.transport;
    if (transport == null) {
      throw StateError('No active transport');
    }
    return transport;
  }

  Future<void> dispose() async {
    await connectionCtrl.close();
    await modeCtrl.close();
    await rawCtrl.close();
    await textCtrl.close();
    await messageCtrl.close();
    await broadcastCtrl.close();
    await errorCtrl.close();
    await deviceInfoCompleteCtrl.close();
    await deviceInfoWatchCtrl.close();
    await storageMutationCtrl.close();
  }
}

String _trimCliResult(String raw, String command) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final commandIndex = normalized.indexOf(command);
  final body = commandIndex >= 0
      ? normalized.substring(commandIndex + command.length)
      : normalized;
  final bodyPromptIndex = body.lastIndexOf('>: ');
  return (bodyPromptIndex >= 0 ? body.substring(0, bodyPromptIndex) : body)
      .trim();
}
