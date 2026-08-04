import 'dart:async';
import 'dart:typed_data';


import '../../common/log.dart';
import '../../model/discovered.dart';
import '../../model/enums.dart';
import '../../model/exceptions.dart';
import '../transport.dart';
import 'gatt.dart';
import 'ops.dart';

abstract class UniversalBleTransportBase extends Transport {
  static const String overflowCharUuid = '19ed82ae-ed21-4c9d-4145-228e63fe0000';
  static const String rpcStatusCharUuid =
      '19ed82ae-ed21-4c9d-4145-228e64fe0000';
  static const int _minBleMtuSize = 20;
  // Firmware RPC_BUFFER_SIZE (serial_service.c). The firmware resets this buffer
  // on a fresh connection and grants the full 1024-byte credit, so this is the
  // initial flow-control credit to assume when the first credit read races ahead
  // of that grant and returns 0.
  static const int _rpcBufferSize = 1024;
  // DO NOT CHANGE: 160 is the empirically stable ATT write payload for this
  // firmware. Raising it toward the 411-byte ATT_MTU ceiling makes link drops
  // far more frequent.
  static const int maxBleMtuSize = 160;
  // Bound for the unencrypted GATT setup steps (MTU negotiation, service
  // discovery).
  static const Duration _gattOpTimeout = Duration(seconds: 15);
  // Per-attempt bound for the encrypted setup ops (subscribe/read) that trigger
  // pairing. universal_ble's command queue otherwise applies a 10 s default that
  // killed the read while the user was still typing the PIN. This is generous on
  // purpose (PIN entry is slow); on expiry _runPairingSensitive just retries, so
  // the effective wait is unbounded until the link drops or the user cancels.
  static const Duration _pairingOpTimeout = Duration(minutes: 5);
  // Bound for a single ATT write callback before it is treated as lost.
  static const Duration _writeCallbackTimeout = Duration(seconds: 15);
  // TX stall watchdog: with data pending, the firmware must grant credit /
  // activate the session well within this window; silence means the session
  // is dead and every queued task must settle instead of hanging.
  static const Duration _stallPoll = Duration(seconds: 5);
  static const int _stallPollLimit = 6;

  // Exactly one transport may own a platform connect attempt at a time. A
  // stale attempt's timeout or close must never disconnect a newer connection.
  static int _connectAttemptGen = 0;
  static UniversalBleTransportBase? _connectionOwner;

  // universal_ble exposes exactly one process-global slot per callback, but
  // multi-session holds several BLE links at once. This static dispatcher
  // owns the global slot and routes each event to the live transport of that
  // device; a transport registers when it takes the link and unregisters when
  // its link dies. The slot itself is never nulled — with no registered
  // transport the dispatch is a no-op.
  static final Map<String, UniversalBleTransportBase> _liveByDevice = {};

  void _registerDispatch() {
    _liveByDevice[_device.device.deviceId] = this;
    _ops.onConnectionChange = _dispatchConnectionChange;
    _ops.onValueChange = _dispatchValueChange;
  }

  static void _dispatchConnectionChange(
    String deviceId,
    bool isConnected,
    String? error,
  ) {
    _liveByDevice[deviceId]?._onConnectionChange(deviceId, isConnected, error);
  }

  static void _dispatchValueChange(
    String deviceId,
    String charId,
    Uint8List value,
    int? mtu,
  ) {
    _liveByDevice[deviceId]?._onValueChange(deviceId, charId, value, mtu);
  }

  // Aborts whatever platform connect is currently in flight, if any. Lets a
  // user-initiated disconnect during the connect window unwind the attempt
  // immediately instead of waiting out _connectTimeout.
  static void abortPendingConnect() => _connectionOwner?._abortConnect();

  final BleDiscoveredDevice _device;
  final BleOps _ops;

  late final String _txSvcId;
  late final String _txCharId;
  late final String _rxSvcId;
  late final String _rxCharId;
  late final bool _txWithResponse;
  late final bool _rxUsesIndicate;
  late int bleMtuSize;

  String? _overflowSvcId;
  String? _overflowCharId;
  String? _rpcStatusSvcId;
  String? _rpcStatusCharId;

  late String _rxCharIdLower;
  late String _overflowCharIdLower;
  late String _rpcStatusCharIdLower;

  final List<BlePendingSend> _txQueue = [];
  Completer<void>? _txDataSignal;

  // Flow-control credit mirror. _budgetGen detects that a fresh authoritative
  // credit notification arrived while a write was in flight.
  int _budget = 0;
  int _budgetGen = 0;
  Completer<void>? _budgetSignal;

  // Firmware RPC session state mirrored from the rpcStatus characteristic.
  bool _rpcSessionActive = false;
  bool _rpcStatusAvailable = false;
  Completer<void>? _rpcActiveSignal;

  Completer<void>? _disconnectSignal;
  // Completes when the user aborts an in-flight connect (see abortPendingConnect)
  // so the platform connect await stops immediately. Live only for the duration
  // of a platform connect await.
  Completer<void>? _connectAbort;
  // Live for the whole pairing reconnect loop in open(). First-time pairing can
  // drop the link by supervision timeout before the user finishes typing the
  // PIN; the loop reconnects and retries until pairing succeeds. This completer
  // is fired when the user cancels (abortPendingConnect) so the loop stops
  // reconnecting instead of retrying forever.
  Completer<void>? _pairingAbort;
  // Completed the instant the link drops (or the transport is closed) while
  // open()/_subscribeRpcStatus are still setting up GATT, so every setup await
  // aborts immediately instead of each waiting out its own multi-second
  // timeout. Without this, a peer disconnect mid-setup wedged connect for the
  // full 15 s GATT window even though the platform already reported the drop.
  Completer<void>? _setupGuard;
  bool _senderRunning = false;
  int _writeTimeoutStreak = 0;
  static const int _maxWriteTimeoutStreak = 2;
  BleLinkState _link = BleLinkState.disconnected;

  // Elapsed-time markers for precise disconnect diagnostics: how long the link
  // survived after the platform reported connected, and after the RPC session
  // (GATT setup) finished opening. A drop a few seconds after either is the
  // signature of a link-layer problem (stale bond / supervision timeout), not
  // anything the RPC layer did.
  final Stopwatch _platformConnectAt = Stopwatch();
  final Stopwatch _sessionOpenAt = Stopwatch();
  int _bytesWrittenSinceOpen = 0;

  UniversalBleTransportBase(this._device, this._ops);

  // Platform hook that runs after all subscriptions are in place
  // (macOS: connection-parameter settle).
  Future<void> openExtra() async {}

  // Aborts this transport's in-flight platform connect: wakes the connect race
  // in configure and tells the platform to stop the pending connection so
  // CoreBluetooth/BlueZ does not keep it pending in the background.
  void _abortConnect() {
    final abort = _connectAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    // Also stop the pairing reconnect loop so a cancel during PIN entry does not
    // immediately reconnect and retry.
    final pairing = _pairingAbort;
    if (pairing != null && !pairing.isCompleted) pairing.complete();
    unawaited(
      _ops.disconnect(_device.device.deviceId).catchError((Object e) {
        Log.error('[BLE] abort-connect cancel failed: $e');
      }),
    );
  }

  Future<void> configure() async {
    final deviceId = _device.device.deviceId;
    final connectAttempt = ++_connectAttemptGen;
    _connectionOwner = this;
    var aborted = false;
    final abort = _connectAbort = Completer<void>();
    // The platform connect is intentionally NOT bounded by a timeout. First-time
    // bonding and bonded-link re-encryption both happen inside this step and can
    // take a long time (the OS may show a PIN prompt the user types at their own
    // pace). A fixed timeout fired mid-bonding and the cleanup disconnect aborted
    // it — on some platforms also dismissing the PIN dialog. A stuck/unreachable
    // attempt is unwound only by the user (dialog Cancel -> abortPendingConnect)
    // or by a newer attempt superseding this one. A genuine platform connect
    // failure still throws out of the await below.
    final connectFuture = _ops.connect(deviceId);
    // If the abort wins the race, the connect future is left to settle on its
    // own (_abortConnect already cancelled it on the platform side); swallow its
    // late outcome so it does not surface as an unhandled async error.
    unawaited(connectFuture.catchError((_) {}));
    try {
      // Race the platform connect against a user abort: whichever resolves
      // first ends the wait.
      await Future.any<void>([
        connectFuture,
        abort.future.then((_) => aborted = true),
      ]);
    } finally {
      if (identical(_connectAbort, abort)) _connectAbort = null;
    }
    if (aborted) {
      if (connectAttempt == _connectAttemptGen &&
          identical(_connectionOwner, this)) {
        _connectionOwner = null;
      }
      throw FlipperTransportError('BLE connect aborted');
    }
    _link = BleLinkState.established;
    _platformConnectAt
      ..reset()
      ..start();
    if (connectAttempt != _connectAttemptGen) {
      // A newer attempt owns the platform link now; do not touch it.
      throw StateError('BLE connection attempt superseded');
    }
    try {
      await configureConnected(deviceId);
    } catch (_) {
      // The factory never returns this transport, so nobody will close() it:
      // the platform link must be released here or it leaks as a ghost
      // connection.
      if (identical(_connectionOwner, this)) {
        _connectionOwner = null;
        _link = BleLinkState.disconnected;
        unawaited(
          _ops.disconnect(deviceId).catchError((Object e) {
            Log.error('[BLE] cleanup disconnect failed: $e');
          }),
        );
      }
      rethrow;
    }
  }

  Future<void> configureConnected(String deviceId) async {
    int negotiatedMtu = 23;
    try {
      negotiatedMtu = await _ops
          .requestMtu(deviceId, 517)
          .timeout(_gattOpTimeout);
    } catch (e) {
      Log.error(
        '[BLE] requestMtu failed: $e (using default $negotiatedMtu)',
      );
    }

    // Every GATT step is bounded: a platform stack that never answers (a
    // classic CoreBluetooth/BlueZ failure mode) would otherwise wedge the
    // lifecycle chain forever — including the user's disconnect().
    final List<BleService> services;
    try {
      services = await _ops
          .discoverServices(deviceId)
          .timeout(_gattOpTimeout);
    } on TimeoutException {
      throw FlipperTransportError(
        'BLE service discovery timed out after ${_gattOpTimeout.inSeconds}s',
      );
    }
    String? txSvc;
    String? txChar;
    String? rxSvc;
    String? rxChar;
    String? overflowSvc;
    String? overflowChar;
    String? rpcStatusSvc;
    String? rpcStatusChar;
    var txWithResponse = true;
    var rxUsesIndicate = false;

    for (final service in services) {
      final sid = service.uuid.toLowerCase();
      if (sid != flipperBleServiceUuid) continue;
      for (final char in service.characteristics) {
        final cid = char.uuid.toLowerCase();
        if (cid == flipperBleTxUuid) {
          txSvc = service.uuid;
          txChar = char.uuid;
          // Write WITH response: each ATT write is acknowledged by the
          // peripheral before the next one goes out. Empirically stable on
          // this firmware; do not switch to write-without-response.
          txWithResponse = char.canWrite;
        }
        if (cid == flipperBleRxUuid) {
          rxSvc = service.uuid;
          rxChar = char.uuid;
          rxUsesIndicate = char.canIndicate;
        }
        if (cid == overflowCharUuid) {
          overflowSvc = service.uuid;
          overflowChar = char.uuid;
        }
        if (cid == rpcStatusCharUuid) {
          rpcStatusSvc = service.uuid;
          rpcStatusChar = char.uuid;
        }
      }
    }

    final missing = <String>[
      if (txSvc == null || txChar == null) 'tx($flipperBleTxUuid)',
      if (rxSvc == null || rxChar == null) 'rx($flipperBleRxUuid)',
      if (overflowSvc == null || overflowChar == null)
        'overflow($overflowCharUuid)',
      if (rpcStatusSvc == null || rpcStatusChar == null)
        'rpcStatus($rpcStatusCharUuid)',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing Flipper BLE characteristics: ${missing.join(', ')}',
      );
    }

    _txSvcId = txSvc!;
    _txCharId = txChar!;
    _rxSvcId = rxSvc!;
    _rxCharId = rxChar!;
    _txWithResponse = txWithResponse;
    _rxUsesIndicate = rxUsesIndicate;
    bleMtuSize = (negotiatedMtu - 3).clamp(_minBleMtuSize, maxBleMtuSize);
    _overflowSvcId = overflowSvc;
    _overflowCharId = overflowChar;
    _rpcStatusSvcId = rpcStatusSvc;
    _rpcStatusCharId = rpcStatusChar;
    _rxCharIdLower = _rxCharId.toLowerCase();
    _overflowCharIdLower = _overflowCharId!.toLowerCase();
    _rpcStatusCharIdLower = _rpcStatusCharId!.toLowerCase();
    Log.info(
      '[BLE] configured: negotiatedMtu=$negotiatedMtu mtu=$bleMtuSize '
      'txWithResponse=$_txWithResponse',
    );
  }

  @override
  bool get supportsCli => false;

  @override
  FlipperMode get initialMode => FlipperMode.rpc;

  @override
  Future<void> open() async {
    _connectionOwner = this;
    _registerDispatch();
    // The platform link is already up here (configure connected it).
    _link = BleLinkState.connected;

    final deviceId = _device.device.deviceId;
    // First-time pairing reconnect loop. The encrypted setup below triggers the
    // system PIN prompt; on a never-bonded device the BLE link is frequently
    // dropped by the controller (supervision/pairing timeout, wasDisconnecting=
    // false) before the user finishes typing the PIN. Once the PIN is accepted
    // the OS stores the bond, so reconnecting and retrying eventually succeeds
    // over an encrypted link. Loop until setup completes or the user cancels
    // (Cancel -> abortPendingConnect -> _pairingAbort).
    final pairingAbort = _pairingAbort = Completer<void>();
    try {
      var attempt = 0;
      while (true) {
        _setupGuard = Completer<void>();
        try {
          await _openEncryptedSetup(deviceId);
          break;
        } catch (e) {
          if (pairingAbort.isCompleted) {
            throw FlipperTransportError('BLE connect aborted');
          }
          if (!_isPairingDrop(e)) rethrow;
          attempt++;
          Log.info(
            '[BLE] link dropped during first-time pairing (attempt $attempt); '
            'reconnecting so the user can finish entering the PIN',
          );
          final reconnected = await _reconnectForPairing(deviceId, pairingAbort);
          if (!reconnected) {
            throw FlipperTransportError('BLE connect aborted');
          }
        }
      }
    } finally {
      if (identical(_pairingAbort, pairingAbort)) _pairingAbort = null;
    }

    await _subscribeRpcStatus(deviceId);
    await openExtra();
    // A drop during the rpcStatus subscribe (swallowed below) or the openExtra
    // settle must not commit a dead transport; fail the connect honestly.
    if (!isActive) {
      throw FlipperTransportError(
        'BLE link dropped during session setup '
        '(${closeReason ?? 'disconnected'})',
      );
    }
    _sessionOpenAt
      ..reset()
      ..start();
    _bytesWrittenSinceOpen = 0;
    _startSender();
    Log.info('[BLE] transport open (rpcSession=$_rpcSessionActive)');
  }

  // Awaits a setup GATT operation, but bails out the instant the link drops
  // mid-flight (_setupGuard) instead of waiting out the full [timeout]. The
  // underlying op is left to settle on its own and its result is ignored. A
  // null [timeout] waits indefinitely (used for the pairing-sensitive steps,
  // see _runPairingSensitive): the only thing that ends the wait is the op
  // settling or the link actually dropping.
  Future<T> _awaitSetup<T>(Future<T> op, [Duration? timeout]) {
    final guard = _setupGuard;
    if (guard == null) return timeout == null ? op : op.timeout(timeout);
    final completer = Completer<T>();
    op.then(
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    guard.future.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          FlipperTransportError(
            'BLE link dropped during session setup '
            '(${closeReason ?? 'disconnected'})',
          ),
        );
      }
    });
    final future = completer.future;
    return timeout == null ? future : future.timeout(timeout);
  }

  // Runs a setup GATT operation that may trigger first-time BLE pairing.
  //
  // On Apple (macOS/iOS) there is no blocking system-pairing API: the first
  // access to an encrypted characteristic of an un-bonded device makes
  // CoreBluetooth kick off pairing IN THE BACKGROUND (showing the system PIN
  // prompt) and IMMEDIATELY return "Encryption is insufficient" (CBATTError 15)
  // instead of waiting. If that error is treated as fatal, open() throws and the
  // client closes the link (cancelPeripheralConnection) — which aborts the
  // in-flight pairing and makes the PIN prompt vanish the instant it appeared.
  //
  // So we never tear the link down on that error: we just retry the op while
  // pairing is still in progress, waiting as long as the user needs to type the
  // PIN. The loop ends only when the op finally succeeds (pairing done) or the
  // link genuinely drops (_setupGuard, e.g. the user cancels the connect).
  Future<T> _runPairingSensitive<T>(Future<T> Function() op) async {
    var logged = false;
    while (true) {
      final guard = _setupGuard;
      if (guard == null || guard.isCompleted) {
        // No active setup (or the link already dropped): run once, no retry.
        return _awaitSetup(op());
      }
      try {
        return await _awaitSetup(op());
      } on FlipperTransportError {
        // _setupGuard fired: the link really dropped — propagate, do not loop.
        rethrow;
      } catch (e) {
        // Retry while pairing is in progress: either the device answered
        // "insufficient encryption" (pairing not done yet) or the op exceeded
        // _pairingOpTimeout while the user was still typing the PIN. Anything
        // else is a real error.
        if (!_isInsufficientEncryption(e) && e is! TimeoutException) rethrow;
        if (!logged) {
          Log.info(
            '[BLE] encrypted characteristic needs pairing; awaiting PIN entry '
            '(retrying without tearing the link down)',
          );
          logged = true;
        }
        // Pairing is running in the background; give the user time and retry.
        // Bail immediately if the link drops while we wait.
        await Future.any<void>([
          Future<void>.delayed(const Duration(milliseconds: 800)),
          guard.future,
        ]);
      }
    }
  }

  static bool _isInsufficientEncryption(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('insufficient encryption') ||
        s.contains('encryption is insufficient') ||
        s.contains('insufficient authentication') ||
        s.contains('authentication is insufficient');
  }

  // The encrypted GATT setup steps. _runPairingSensitive retries each on
  // "insufficient encryption" while the link is alive (pairing in progress); a
  // real link drop surfaces as a FlipperTransportError that open()'s reconnect
  // loop handles.
  //
  // ORDER MATTERS. Establish encryption FIRST (a read of an encrypted
  // characteristic triggers pairing and blocks until it completes), only THEN
  // subscribe: on Apple a notification subscribe (CCCD write) registered on an
  // UNencrypted link silently fails to activate, so the firmware's credit/RX
  // notifications never arrive and TX stalls forever with budget=0 ("waiting for
  // overflow credit").
  //
  // The pairing trigger reads the rpcStatus characteristic, NOT the overflow
  // one. The overflow characteristic must be read EXACTLY ONCE per session (for
  // the initial credit): reading it returns the stored credit rather than a
  // fresh grant, and an extra read desyncs the firmware's flow-control counter,
  // which later trips ERROR_DECODE and makes the firmware reset its BLE stack
  // (seen as a PEER-INITIATED drop minutes in). rpcStatus is a plain status read
  // with no such side effect.
  Future<void> _openEncryptedSetup(String deviceId) async {
    // 1. Pair / establish encryption via a side-effect-free encrypted read.
    final rpcSvc = _rpcStatusSvcId;
    final rpcChr = _rpcStatusCharId;
    if (rpcSvc != null && rpcChr != null) {
      await _runPairingSensitive(
        () => _ops.read(deviceId, rpcSvc, rpcChr, timeout: _pairingOpTimeout),
      );
    } else {
      // rpcStatus is a required characteristic (see configureConnected), so
      // this fallback should be unreachable; pair via overflow only if it is
      // somehow absent.
      await _runPairingSensitive(
        () => _ops.read(
          deviceId,
          _overflowSvcId!,
          _overflowCharId!,
          timeout: _pairingOpTimeout,
        ),
      );
    }

    // 2. RX notifications, now on the encrypted link.
    if (_rxUsesIndicate) {
      await _runPairingSensitive(
        () => _ops.subscribeIndications(
          deviceId,
          _rxSvcId,
          _rxCharId,
          timeout: _pairingOpTimeout,
        ),
      );
    } else {
      await _runPairingSensitive(
        () => _ops.subscribeNotifications(
          deviceId,
          _rxSvcId,
          _rxCharId,
          timeout: _pairingOpTimeout,
        ),
      );
    }

    // 3. Overflow (flow-control credit) notifications, on the encrypted link.
    await _runPairingSensitive(
      () => _ops.subscribeNotifications(
        deviceId,
        _overflowSvcId!,
        _overflowCharId!,
        timeout: _pairingOpTimeout,
      ),
    );

    // 4. Authoritative initial credit — the ONLY overflow read of the session.
    final initialBudget = await _runPairingSensitive(
      () => _ops.read(
        deviceId,
        _overflowSvcId!,
        _overflowCharId!,
        timeout: _pairingOpTimeout,
      ),
    );
    _applyOverflowValue(initialBudget);

    // A fresh connection resets the firmware RPC buffer and grants the full
    // 1024-byte credit. If the read above raced ahead of that grant and saw 0,
    // seed the standard buffer size so the first TX cycle is not stalled waiting
    // for a credit notification that effectively already happened.
    if (_budget <= 0) {
      _budget = _rpcBufferSize;
      _budgetGen += 1;
      Log.info(
        '[BLE] initial overflow credit was 0; seeding RPC_BUFFER_SIZE '
        '($_rpcBufferSize) on fresh connection',
      );
    }
  }

  // True when [e] signals the link dropped mid-setup (the _setupGuard error).
  // During first-time pairing that drop is the controller giving up before the
  // PIN was entered, not a fatal error — open() reconnects and retries.
  static bool _isPairingDrop(Object e) {
    if (e is! FlipperTransportError) return false;
    return e.toString().toLowerCase().contains(
      'link dropped during session setup',
    );
  }

  // Re-establishes the platform link after it dropped mid-pairing, retrying
  // until the link is back up (services rediscovered) or the user cancels.
  // Returns true when the link is ready for another setup attempt, false if the
  // user aborted. A fault clears the callbacks/ownership, so they are restored
  // here before each connect.
  Future<bool> _reconnectForPairing(
    String deviceId,
    Completer<void> pairingAbort,
  ) async {
    while (!pairingAbort.isCompleted) {
      // Let the platform finish tearing the old link down before reconnecting;
      // an instant re-connect races CoreBluetooth/BlueZ cleanup.
      await Future.any<void>([
        Future<void>.delayed(const Duration(milliseconds: 600)),
        pairingAbort.future,
      ]);
      if (pairingAbort.isCompleted) return false;

      _connectionOwner = this;
      _registerDispatch();

      var aborted = false;
      final abort = _connectAbort = Completer<void>();
      final connectFuture = _ops.connect(deviceId);
      unawaited(connectFuture.catchError((_) {}));
      try {
        await Future.any<void>([
          // Settle on success OR failure without rethrowing — a failed connect
          // is just retried below, not propagated.
          connectFuture.then((_) {}, onError: (_) {}),
          abort.future.then((_) => aborted = true),
          pairingAbort.future.then((_) => aborted = true),
        ]);
      } finally {
        if (identical(_connectAbort, abort)) _connectAbort = null;
      }
      if (aborted || pairingAbort.isCompleted) return false;

      // connectFuture may have failed; confirm the link is actually up.
      final state = await _ops.getConnectionState(deviceId);
      if (state != BleConnState.connected) {
        Log.info('[BLE] pairing reconnect: link not up yet, retrying');
        continue;
      }
      _link = BleLinkState.established;
      // universal_ble requires a fresh discovery after each connect before GATT
      // ops; the char IDs parsed in configure stay valid.
      try {
        await _ops.discoverServices(deviceId).timeout(_gattOpTimeout);
      } catch (e) {
        Log.error('[BLE] pairing reconnect: discoverServices failed: $e');
        continue;
      }
      _link = BleLinkState.connected;
      return true;
    }
    return false;
  }

  Future<void> _subscribeRpcStatus(String deviceId) async {
    final svc = _rpcStatusSvcId;
    final chr = _rpcStatusCharId;
    if (svc == null || chr == null) return;
    try {
      await _ops
          .subscribeNotifications(deviceId, svc, chr)
          .timeout(const Duration(seconds: 4));
      final initial = await _ops.read(deviceId, svc, chr);
      _rpcStatusAvailable = true;
      _applyRpcStatusValue(initial);
    } catch (e) {
      // Without rpcStatus, session readiness cannot be observed; fall back to
      // ungated TX instead of holding the queue forever.
      _rpcStatusAvailable = false;
      Log.error('[BLE] rpcStatus unavailable, TX gating disabled: $e');
    }
  }

  void _onConnectionChange(String deviceId, bool isConnected, String? error) {
    if (deviceId != _device.device.deviceId) return;
    if (isConnected) return;
    final wasDisconnecting = _link == BleLinkState.disconnecting;
    final platformError = error?.trim();
    final cause = _classifyBleDisconnect(platformError);
    final reason = platformError == null || platformError.isEmpty
        ? 'backend connectionChange disconnected without platform reason '
              '(likely supervision timeout / peer reset / out of range)'
        : 'backend connectionChange disconnected: $platformError';
    final diagnostics =
        'link=${_link.name} budget=$_budget txPending=${_txQueue.length} '
        'rpcSession=${_rpcStatusAvailable ? _rpcSessionActive : 'unknown'}';

    // Precise, single-line disconnect record. linkUpMs/sessionUpMs pin down the
    // failure to the link layer: a drop within a few seconds of either, with
    // little or no TX, cannot be the RPC layer's doing. cause= decodes the
    // CoreBluetooth localizedDescription (the only field universal_ble forwards)
    // into the concrete CBError meaning and what to do about it.
    final linkUpMs = _platformConnectAt.isRunning
        ? '${_platformConnectAt.elapsedMilliseconds}'
        : 'n/a';
    final sessionUpMs = _sessionOpenAt.isRunning
        ? '${_sessionOpenAt.elapsedMilliseconds}'
        : 'setup-incomplete';
    Log.info(
      '[BLE] disconnect diagnostics: cause=$cause '
      'linkUpMs=$linkUpMs sessionUpMs=$sessionUpMs '
      'bytesWrittenSinceOpen=$_bytesWrittenSinceOpen mtu=$bleMtuSize '
      'txWithResponse=$_txWithResponse rxIndicate=$_rxUsesIndicate '
      '$diagnostics wasDisconnecting=$wasDisconnecting '
      'rawError="${platformError ?? 'none'}"',
    );

    // During the first-time pairing reconnect loop a link drop is expected (the
    // controller gives up before the PIN is entered). onTransportFault would
    // close the transport IRREVERSIBLY (bytesStream closed, isActive=false), so
    // it must not run here: just mark the link down and wake the setup awaits so
    // open() can reconnect and retry. Keep _connectionOwner/callbacks intact so a
    // user Cancel still routes through _abortConnect and the reconnect can reuse
    // them.
    if (_inPairingLoop && !wasDisconnecting) {
      _link = BleLinkState.disconnected;
      _rpcSessionActive = false;
      final signal = _disconnectSignal;
      _disconnectSignal = null;
      fireOnce(signal);
      fireOnce(_setupGuard);
      Log.info(
        '[BLE] pairing-phase link drop; reconnecting (transport kept alive)',
      );
      return;
    }

    _markBleDisconnected();
    if (!wasDisconnecting) {
      onTransportFault(FlipperTransportError('BLE $reason [$cause] ($diagnostics)'));
    }
  }

  // True while open()'s first-time pairing reconnect loop is running. A link
  // drop in this window is recoverable (reconnect + retry), not a fatal fault.
  bool get _inPairingLoop {
    final p = _pairingAbort;
    return p != null && !p.isCompleted;
  }

  // Decodes the CoreBluetooth localizedDescription (CBErrorDomain /
  // CBATTErrorDomain) into the concrete failure class. universal_ble only
  // forwards the localized string, but each string maps 1:1 to a CBError code,
  // so this is exact — not a guess. The labels call out the actionable cases
  // (stale bond / encryption) so they are unmistakable in the log.
  static String _classifyBleDisconnect(String? platformError) {
    final e = platformError?.toLowerCase() ?? '';
    if (e.isEmpty) {
      return 'NO-REASON (supervision timeout / peer reset / out of range)';
    }
    if (e.contains('pairing') || e.contains('bond')) {
      return 'STALE-BOND CBError.peerRemovedPairingInformation — '
          'forget device on BOTH Mac BT settings and Flipper, then re-pair';
    }
    if (e.contains('encryption') || e.contains('authentication')) {
      return 'ENCRYPTION/AUTH failure — bonding keys mismatch; re-pair both sides';
    }
    if (e.contains('timed out') || e.contains('timeout')) {
      return 'SUPERVISION-TIMEOUT CBError.connectionTimeout — link lost packets '
          '(conn params / RF / coexistence), not an RPC issue';
    }
    if (e.contains('disconnected from us') ||
        e.contains('peripheral disconnected') ||
        e.contains('peripheral is disconnected')) {
      return 'PEER-INITIATED CBError.peripheralDisconnected — firmware closed '
          'the link (decode error / its BLE stack reset)';
    }
    if (e.contains('connection failed')) {
      return 'CONNECTION-FAILED CBError.connectionFailed';
    }
    if (e.contains('too many') || e.contains('limit')) {
      return 'LE-DEVICE-LIMIT CBError.tooManyLEPairedDevices — forget some bonds';
    }
    return 'UNCLASSIFIED (see rawError)';
  }

  void _onValueChange(
    String deviceId,
    String charId,
    Uint8List value,
    int? mtu,
  ) {
    if (deviceId != _device.device.deviceId) return;
    final lower = charId.toLowerCase();
    if (lower == _rxCharIdLower) {
      addBytes(value);
      return;
    }
    if (lower == _overflowCharIdLower) {
      _applyOverflowValue(value);
      return;
    }
    if (lower == _rpcStatusCharIdLower) {
      _applyRpcStatusValue(value);
    }
  }

  void _applyOverflowValue(List<int> value) {
    final bytes = value is Uint8List ? value : Uint8List.fromList(value);
    final view = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    // serial_service.c stores the credit big-endian (REVERSE_BYTES_U32).
    int remaining;
    if (bytes.length >= 4) {
      remaining = view.getUint32(0, Endian.big);
    } else if (bytes.length >= 2) {
      remaining = view.getUint16(0, Endian.big);
    } else {
      Log.error('[BLE] overflow value too short (${bytes.length} bytes)');
      return;
    }
    _budget = remaining;
    _budgetGen += 1;
    if (Log.debugOn) {
      Log.debug(
        '[BLE] credit granted: $remaining bytes (gen $_budgetGen)',
      );
    }
    final signal = _budgetSignal;
    _budgetSignal = null;
    fireOnce(signal);
  }

  void _applyRpcStatusValue(List<int> value) {
    final active = value.any((b) => b != 0);
    if (active == _rpcSessionActive) return;
    _rpcSessionActive = active;
    Log.info('[BLE] rpcSession=${active ? 'active' : 'inactive'}');
    if (active) {
      final signal = _rpcActiveSignal;
      _rpcActiveSignal = null;
      fireOnce(signal);
      return;
    }
    if (!isActive || _link != BleLinkState.connected) return;
    // The firmware deactivates the session right before tearing the link down
    // (e.g. after a decode error); report the real cause now.
    onTransportFault(
      FlipperTransportError('Flipper closed the RPC session (rpcStatus=0)'),
    );
  }

  @override
  Future<void> rawWrite(Uint8List bytes) {
    if (!isActive) {
      return Future.error(StateError('BLE transport closed'));
    }
    if (bytes.isEmpty) return Future.value();

    // Resolves only after the complete frame crossed every overflow-credit
    // boundary, keeping the RPC worker blocked until then.
    final pending = BlePendingSend(bytes);
    _txQueue.add(pending);
    final signal = _txDataSignal;
    _txDataSignal = null;
    fireOnce(signal);
    _startSender();
    return pending.future;
  }

  void _startSender() {
    if (_senderRunning) return;
    _senderRunning = true;
    unawaited(_runSender());
  }

  Future<void> _runSender() async {
    var sessionPolls = 0;
    var budgetPolls = 0;
    while (isActive) {
      if (_txQueue.isEmpty) {
        sessionPolls = 0;
        budgetPolls = 0;
        final signal = _txDataSignal = Completer<void>();
        await signal.future;
        continue;
      }

      if (_rpcStatusAvailable && !_rpcSessionActive) {
        final signal = _rpcActiveSignal = Completer<void>();
        if (await _awaitSignal(signal, _stallPoll)) {
          sessionPolls = 0;
          continue;
        }
        sessionPolls++;
        if (sessionPolls == 1) {
          Log.info('[BLE] TX held: firmware RPC session not active');
        }
        if (sessionPolls >= _stallPollLimit && isActive) {
          onTransportFault(
            FlipperTransportError(
              'Firmware RPC session did not become active within '
              '${_stallPoll.inSeconds * _stallPollLimit}s with TX pending',
            ),
          );
          break;
        }
        continue;
      }
      sessionPolls = 0;

      if (_budget <= 0) {
        final signal = _budgetSignal = Completer<void>();
        if (await _awaitSignal(signal, _stallPoll)) {
          budgetPolls = 0;
          continue;
        }
        if (identical(_budgetSignal, signal)) _budgetSignal = null;
        budgetPolls++;
        if (budgetPolls == 1) {
          // Reading the characteristic would return its stored value, not a
          // fresh credit, and could overrun the firmware's 1024-byte buffer.
          Log.info('[BLE] TX held: waiting for overflow credit');
        }
        if (budgetPolls >= _stallPollLimit && isActive) {
          onTransportFault(
            FlipperTransportError(
              'No flow-control credit for '
              '${_stallPoll.inSeconds * _stallPollLimit}s with TX pending',
            ),
          );
          break;
        }
        continue;
      }
      budgetPolls = 0;

      await _drainBudgetCycle();
    }
    _senderRunning = false;
  }

  // Sends queued frames within one credit cycle; never sends a single byte
  // beyond the credit the firmware granted.
  Future<void> _drainBudgetCycle() async {
    var cycleRemaining = _budget;
    final cycleGen = _budgetGen;
    _budget = 0;

    while (isActive && cycleRemaining > 0) {
      if (_txQueue.isEmpty) {
        final signal = _txDataSignal = Completer<void>();
        final arrived = await _awaitSignal(
          signal,
          const Duration(milliseconds: 100),
        );
        if (!arrived || _txQueue.isEmpty) break;
      }

      final pending = _txQueue.first;
      final sendLength = pending.remainingLength < cycleRemaining
          ? pending.remainingLength
          : cycleRemaining;
      final sendEnd = pending.offset + sendLength;
      try {
        await _sendMessage(
          Uint8List.sublistView(pending.bytes, pending.offset, sendEnd),
        );
      } catch (e) {
        if (isActive) {
          onTransportFault(FlipperTransportError('BLE write failed: $e'));
        }
        return;
      }

      pending.offset = sendEnd;
      cycleRemaining -= sendLength;
      if (pending.offset == pending.bytes.length) {
        // _failAllPending (called from onFaultExtra during the await above) may
        // have cleared _txQueue; guard before removeAt to avoid RangeError.
        if (_txQueue.isNotEmpty && identical(pending, _txQueue.first)) {
          _txQueue.removeAt(0);
        }
        pending.complete();
      }
      // A fresh credit notification is authoritative: it already accounts for
      // everything sent so far, so the old cycle's remainder must be dropped.
      if (_budgetGen != cycleGen) return;
    }

    // The firmware re-grants only after the whole credit is consumed; keep the
    // unused remainder for later frames.
    if (cycleRemaining > 0 && _budgetGen == cycleGen) {
      _budget = cycleRemaining;
    }
  }

  Future<void> _sendMessage(Uint8List data) async {
    var offset = 0;
    while (offset < data.length) {
      if (!isActive) {
        throw StateError('BLE transport closed');
      }
      final chunkEnd = (offset + bleMtuSize).clamp(0, data.length);
      try {
        // The explicit timeout also covers platform stacks whose write future
        // silently never completes — without it the sender (and its stall
        // watchdog, which runs in this same loop) would hang forever.
        await _ops
            .write(
              _device.device.deviceId,
              _txSvcId,
              _txCharId,
              Uint8List.sublistView(data, offset, chunkEnd),
              withoutResponse: !_txWithResponse,
            )
            .timeout(_writeCallbackTimeout);
        _writeTimeoutStreak = 0;
      } on TimeoutException {
        // The platform callback can be lost after an acknowledged ATT write.
        // Retrying is unsafe: the peripheral may already have consumed the
        // bytes. Continue once; overflow control and the RPC ACK verify the
        // stream without duplicating this chunk or dropping the BLE link.
        // Two in a row mean the link itself is gone — if the write truly
        // vanished, the byte stream now has a hole and the firmware will
        // declare ERROR_DECODE anyway; fault with the honest reason instead.
        if (!_txWithResponse) rethrow;
        _writeTimeoutStreak++;
        if (_writeTimeoutStreak >= _maxWriteTimeoutStreak) {
          throw FlipperTransportError(
            '$_writeTimeoutStreak consecutive BLE write callbacks lost; '
            'link presumed dead',
          );
        }
        Log.info(
          '[BLE] write callback timed out; continuing without retry',
        );
      }
      _bytesWrittenSinceOpen += chunkEnd - offset;
      offset = chunkEnd;
    }
  }

  Future<bool> _awaitSignal(Completer<void> signal, Duration timeout) {
    final result = Completer<bool>();
    final timer = Timer(timeout, () {
      if (!result.isCompleted) result.complete(false);
    });
    signal.future.whenComplete(() {
      timer.cancel();
      if (!result.isCompleted) result.complete(true);
    });
    return result.future;
  }

  void _releaseSenderSignals() {
    final signals = [_budgetSignal, _txDataSignal, _rpcActiveSignal];
    _budgetSignal = null;
    _txDataSignal = null;
    _rpcActiveSignal = null;
    for (final signal in signals) {
      fireOnce(signal);
    }
  }

  void _failAllPending(Object error) {
    final pendings = List<BlePendingSend>.from(_txQueue);
    _txQueue.clear();
    for (final p in pendings) {
      p.fail(error);
    }
  }

  @override
  void onFaultExtra(Object error) {
    fireOnce(_setupGuard);
    _releaseSenderSignals();
    _failAllPending(error);
    _markBleDisconnected();
    _clearBleCallbacks();
  }

  @override
  Future<void> nudgeCli() async {
    throw FlipperUnsupportedModeError(
      'CLI mode is not available over BLE connections',
    );
  }

  @override
  Future<void> doClose() async {
    // A close() racing an in-flight open() (e.g. a superseded attempt) must
    // unblock its setup awaits too, not just fault-driven teardown.
    fireOnce(_setupGuard);
    _releaseSenderSignals();
    _failAllPending(StateError('BLE transport closed'));
    if (!identical(_connectionOwner, this)) {
      Log.info(
        '[BLE] stale transport closed without platform disconnect '
        '(newer transport owns ${_device.device.deviceId})',
      );
      _markBleDisconnected();
      _clearBleCallbacks();
      return;
    }
    if (_link == BleLinkState.disconnected) {
      // Never reached the platform, or already fully torn down by a fault:
      // nothing to release.
      _connectionOwner = null;
      _clearBleCallbacks();
      return;
    }
    if (_link == BleLinkState.established) {
      // Platform link is up but the GATT session never finished opening (or
      // open() failed mid-setup): release it without the graceful confirmation
      // wait — there is no live session to drain.
      try {
        await _ops.disconnect(_device.device.deviceId);
      } catch (e) {
        Log.error('[BLE] disconnect failed: $e');
      }
      _markBleDisconnected();
      _clearBleCallbacks();
      return;
    }
    _link = BleLinkState.disconnecting;
    final disconnectSignal = _disconnectSignal = Completer<void>();
    final state = await _ops.getConnectionState(_device.device.deviceId);
    if (state == BleConnState.disconnected) {
      _markBleDisconnected();
      _clearBleCallbacks();
      return;
    }
    try {
      await _ops.disconnect(_device.device.deviceId);
    } catch (e) {
      Log.error('[BLE] disconnect failed: $e');
      _markBleDisconnected();
      _clearBleCallbacks();
      return;
    }
    final confirmed = await _awaitSignal(
      disconnectSignal,
      const Duration(seconds: 5),
    );
    Log.info(
      confirmed
          ? '[BLE] disconnected'
          : '[BLE] disconnect event not confirmed within 5s',
    );
    _markBleDisconnected();
    _clearBleCallbacks();
  }

  void _markBleDisconnected() {
    _link = BleLinkState.disconnected;
    _rpcSessionActive = false;
    if (identical(_connectionOwner, this)) {
      _connectionOwner = null;
    }
    final signal = _disconnectSignal;
    _disconnectSignal = null;
    fireOnce(signal);
  }

  void _clearBleCallbacks() {
    final deviceId = _device.device.deviceId;
    if (identical(_liveByDevice[deviceId], this)) {
      _liveByDevice.remove(deviceId);
    }
  }
}

// Ordered platform-link (GAP) lifecycle, the single source of truth for "how
// alive is the BLE link". States advance monotonically:
//   disconnected -> established -> connected -> disconnecting -> disconnected
//   * established  : platform connect() succeeded, GATT session setup (open())
//                    not finished yet — what the old `_platformConnection
//                    Established` bool tracked. Folding that bool in here
//                    removes a second field that had to be hand-synced with
//                    `_link` on every disconnect path.
//   * connected    : subscriptions are up, the RPC session is usable.
//   * disconnecting: close() is draining the link.
//
// This is a *different layer* from `Transport._lifecycle` (active/closing/
// closed), which tracks the logical transport, not the platform link. Invariant
// the two layers must preserve together: a faulted/closed transport is always
// `disconnected` here (onFaultExtra/doClose -> _markBleDisconnected), and the
// transport never reports `isActive` while `_link == disconnected`.
enum BleLinkState { disconnected, established, connected, disconnecting }

class BlePendingSend {
  BlePendingSend(this.bytes);
  final Uint8List bytes;
  final Completer<void> _completer = Completer<void>();
  int offset = 0;

  Future<void> get future => _completer.future;

  int get remainingLength => bytes.length - offset;

  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void fail(Object error) {
    if (!_completer.isCompleted) _completer.completeError(error);
  }
}
