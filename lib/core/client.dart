part of '../flipper_client.dart';

// Facade over N _FlipperSession objects (one per physical link) plus device
// discovery. Exactly one session is "active": every RPC/CLI entry point and
// every public stream routes to it. The other sessions stay connected and
// warm — activate() swaps the routing instantly, with zero radio work.
class FlipperClient {
  static const String bleServiceUuid = '8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000';
  static const String bleRxUuid = '19ed82ae-ed21-4c9d-4145-228e61fe0000';
  static const String bleTxUuid = '19ed82ae-ed21-4c9d-4145-228e62fe0000';
  static const String cliPrompt = '\r\n\r\n>: ';
  static const String startRpcSession = 'start_rpc_session\r';
  static const int _maxRxParseErrorStreak = 3;
  static const Duration _quickDropWindow = Duration(seconds: 30);
  static const int _maxQuickDropStreak = 2;
  static const Duration _reconnectSettle = Duration(milliseconds: 600);

  final _devicesCtrl = StreamController<List<FlipperDevice>>.broadcast();
  final _connectionCtrl = StreamController<FlipperConnectionState>.broadcast();
  final _modeCtrl = StreamController<FlipperMode>.broadcast();
  final _rawCtrl = StreamController<List<int>>.broadcast();
  final _textCtrl = StreamController<String>.broadcast();
  final _messageCtrl = StreamController<Main>.broadcast();
  final _broadcastCtrl = StreamController<Main>.broadcast();
  final _errorCtrl = StreamController<FlipperRpcException>.broadcast();
  final _deviceInfoCompleteCtrl =
      StreamController<Map<String, String>>.broadcast();
  final _deviceInfoWatchCtrl =
      StreamController<Map<String, String>>.broadcast();
  final _storageMutationCtrl = StreamController<void>.broadcast();
  final _sessionsCtrl = StreamController<List<FlipperSessionInfo>>.broadcast();

  final Map<String, FlipperDevice> _devices = {};
  final Map<String, _FlipperSession> _sessions = {};
  final Map<_FlipperSession, StreamSubscription<FlipperConnectionState>>
  _sessionWatches = {};
  final List<StreamSubscription<dynamic>> _activePipes = [];
  _FlipperSession? _active;
  int _activationSeq = 0;

  Future<void> _lifecycleChain = Future.value();
  bool autoReconnect = true;

  StreamSubscription<void>? _usbPresenceSub;

  bool _scanning = false;
  Completer<void>? _scanPhaseInterrupt;
  static const Duration _scanGraceWindow = Duration(seconds: 5);
  Timer? _scanGraceTimer;
  static const Duration _devicesEmitWindow = Duration(milliseconds: 200);
  Timer? _devicesEmitTimer;
  bool _devicesEmitDirty = false;

  static const Set<Main_Content> _heavyStorageContent = {
    Main_Content.storageWriteRequest,
    Main_Content.storageReadRequest,
    Main_Content.storageDeleteRequest,
  };

  static const Set<Main_Content> _mutatingStorageContent = {
    Main_Content.storageWriteRequest,
    Main_Content.storageDeleteRequest,
  };

  // ── Public streams (piped from the active session) ────────────────────────

  Stream<List<FlipperDevice>> get devicesStream => _devicesCtrl.stream;

  Stream<FlipperConnectionState> get connectionStream => _connectionCtrl.stream;

  Stream<FlipperMode> get modeStream => _modeCtrl.stream;

  Stream<List<int>> get rawBytesStream => _rawCtrl.stream;

  Stream<String> get textStream => _textCtrl.stream;

  Stream<Main> get messageStream => _messageCtrl.stream;

  Stream<Main> get broadcastStream => _broadcastCtrl.stream;

  Stream<Main> get notificationStream => _broadcastCtrl.stream;

  Stream<FlipperRpcException> get errorStream => _errorCtrl.stream;

  Stream<void> get storageMutations => _storageMutationCtrl.stream;

  Stream<void> get usbEvents => _usbPlatform.usbEvents;

  Stream<Map<String, String>> get deviceInfoStream =>
      _deviceInfoCompleteCtrl.stream;

  /// Broadcast stream of device-info patches.
  ///
  /// Each event is a partial [Map<String, String>] — subscribers merge it into
  /// their own state. Subscribing has no side-effects.
  Stream<Map<String, String>> get deviceInfoUpdates =>
      _deviceInfoWatchCtrl.stream;

  /// Snapshot stream of every held link (active and warm). Emits on connect,
  /// disconnect, activation swap and any session state change.
  Stream<List<FlipperSessionInfo>> get sessionsStream => _sessionsCtrl.stream;

  // ── Facade state ───────────────────────────────────────────────────────────

  List<FlipperDevice> get devices =>
      List.unmodifiable(_devices.values.toList());

  List<FlipperDevice> listDevices() => devices;

  List<FlipperSessionInfo> get sessions => List.unmodifiable([
    for (final session in _sessions.values)
      FlipperSessionInfo(
        device: session.device,
        connected: session.isConnected,
        connecting: session.isConnecting,
        active: identical(session, _active),
      ),
  ]);

  bool isDeviceConnected(String id, {FlipperLink? link}) =>
      _findSession(id, link: link)?.isConnected ?? false;

  FlipperDevice? get connectedDevice {
    final session = _active;
    return (session != null && session.isConnected) ? session.device : null;
  }

  _FlipperSession? get _connectingSession {
    final active = _active;
    if (active != null && active.isConnecting) return active;
    for (final session in _sessions.values) {
      if (session.isConnecting) return session;
    }
    return null;
  }

  bool get isConnecting => _connectingSession != null;

  FlipperDevice? get connectingDevice => _connectingSession?.device;

  FlipperDevice? get activeDevice => connectedDevice ?? connectingDevice;

  FlipperMode get _mode => _active?._mode ?? FlipperMode.disconnected;

  FlipperMode get mode => _mode;

  bool get isConnected => _active?.isConnected ?? false;

  bool get isScanning => _scanning;

  _Transport? get _transport => _active?._transport;

  bool get storageBusy => _active?.storageBusy ?? false;

  bool get cliExclusive => _active?.cliExclusive ?? false;

  set cliExclusive(bool value) {
    _active?.cliExclusive = value;
  }

  Map<String, String> get deviceInfoCache =>
      _active?.deviceInfoCache ?? const {};

  bool get deviceInfoFetched => _active?._deviceInfoFetched ?? false;

  void publishDeviceInfoPatch(Map<String, String> patch) {
    _active?._publishDeviceInfoPatch(patch);
  }

  Map<String, String> get deviceInfoWatchSnapshot =>
      _active?.deviceInfoWatchSnapshot ?? const {};

  String? getName() => _active?.getName();

  Future<String> awaitName() {
    final session = _active;
    if (session == null) {
      return Future.error(
        StateError('Cannot fetch device info: no active transport'),
      );
    }
    return session.awaitName();
  }

  Future<Map<String, String>> awaitDeviceInfo() {
    final session = _active;
    if (session == null) {
      return Future.error(
        StateError('Cannot fetch device info: no active transport'),
      );
    }
    return session.awaitDeviceInfo();
  }

  int nextCommandId() => _requireActiveSession().nextCommandId();

  _FlipperSession _requireActiveSession() {
    final session = _active;
    if (session == null) {
      throw StateError('No active transport');
    }
    return session;
  }

  // ── Discovery ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    await _blePlatform.requestPermissions();
  }

  Future<List<FlipperDevice>> refreshDevices({
    Duration bleTimeout = const Duration(seconds: 10),
  }) async {
    _devices.clear();
    for (final session in _sessions.values) {
      if (session.isConnected || session.isConnecting) {
        _rememberDevice(session.device);
      }
    }
    await _loadUsbDevices();
    _emitDevices(immediate: true);
    await scanBle(timeout: bleTimeout);
    return devices;
  }

  Future<List<FlipperDevice>> searchDevices({
    Duration bleTimeout = const Duration(seconds: 10),
  }) {
    return refreshDevices(bleTimeout: bleTimeout);
  }

  Future<void> scanBle({Duration timeout = const Duration(seconds: 10)}) async {
    if (_scanning) return;
    _scanning = true;

    try {
      if (_scanBlocked) {
        Log.info('[BLE] scan skipped: a connection is in progress');
        return;
      }

      final state = await uble.UniversalBle.getBluetoothAvailabilityState();
      if (state != uble.AvailabilityState.poweredOn) {
        Log.info('[FlipperClient] BLE adapter state: $state');
        return;
      }

      await _loadKnownBleDevices();

      uble.UniversalBle.onScanResult = (device) {
        final discovered = BleDiscoveredDevice(device);
        if (Log.debugOn) {
          Log.debug(
            '[BLE] scan result id=${discovered.id} name=${discovered.name} '
            'rssi=${discovered.rssi} services=${device.services}',
          );
        }
        _rememberDevice(_fromDiscovered(discovered));
        if (_hasFilteredBleDevice()) _armScanGrace();
      };

      // Single phase scanning every advertising device: Flipper identification
      // is name/service based (includeDevice), so the UI filter can also
      // reveal non-Flipper devices on demand.
      Log.info('[BLE] scan started');
      await uble.UniversalBle.startScan();
      try {
        final interrupt = _scanPhaseInterrupt = Completer<void>();
        await Future.any([Future.delayed(timeout), interrupt.future]);
        if (identical(_scanPhaseInterrupt, interrupt)) {
          _scanPhaseInterrupt = null;
        }
      } finally {
        _scanGraceTimer?.cancel();
        _scanGraceTimer = null;
        await uble.UniversalBle.stopScan();
        uble.UniversalBle.onScanResult = null;
      }
    } finally {
      _scanning = false;
      _emitDevices(immediate: true);
    }
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    _interruptScanPhase();
    await uble.UniversalBle.stopScan();
    uble.UniversalBle.onScanResult = null;
    _scanning = false;
    _emitDevices(immediate: true);
  }

  void _armScanGrace() {
    if (_scanGraceTimer != null || _scanPhaseInterrupt == null) return;
    Log.info(
      '[BLE] Flipper found; scanning '
      '${_scanGraceWindow.inSeconds}s more for additional units',
    );
    _scanGraceTimer = Timer(_scanGraceWindow, _interruptScanPhase);
  }

  void _interruptScanPhase() {
    _scanGraceTimer?.cancel();
    _scanGraceTimer = null;
    final interrupt = _scanPhaseInterrupt;
    _scanPhaseInterrupt = null;
    _fireOnce(interrupt);
  }

  // Scanning is refused only while a connect attempt is in flight (the radio
  // is busy establishing a link). Live sessions do not block scans: finding a
  // second device while one is connected is the point of multi-session.
  bool get _scanBlocked => isConnecting;

  // Already-bonded / system-connected BLE devices: an instant platform lookup,
  // no radio scan. Lets callers reconnect to a remembered device without
  // paying the full scan timeout.
  Future<List<FlipperDevice>> refreshBleKnown() async {
    await _loadKnownBleDevices();
    _emitDevices(immediate: true);
    return devices;
  }

  Future<void> _loadKnownBleDevices() async {
    for (final device in await _blePlatform.loadKnownDevices()) {
      _rememberDevice(_fromDiscovered(device));
    }
  }

  Future<List<FlipperDevice>> refreshUsbOnly() async {
    final usbKeyPrefix = '${FlipperLink.usb.name}:';
    final held = <FlipperDevice>{
      for (final session in _sessions.values)
        if (session.isConnected || session.isConnecting) session.device,
    };
    _devices.removeWhere(
      (key, device) => key.startsWith(usbKeyPrefix) && !held.contains(device),
    );
    await _loadUsbDevices();
    _emitDevices(immediate: true);
    return devices;
  }

  Future<List<FlipperDevice>> _loadUsbDevices() async {
    final result = await _usbPlatform.loadDevices();
    for (final device in result) {
      _rememberDevice(device);
    }
    return result;
  }

  bool _hasFilteredBleDevice() {
    return _devices.values.any(
      (device) => device.isBle && isFlipperDevice(device),
    );
  }

  bool isFlipperDevice(FlipperDevice device) {
    final source = device.source;
    if (source is BleDiscoveredDevice) {
      return _blePlatform.includeDevice(source);
    }
    if (source is UsbDiscoveredDevice) {
      return _usbPlatform.includeDevice(device);
    }
    return false;
  }

  FlipperDevice _fromDiscovered(DiscoveredDevice device) {
    if (device is BleDiscoveredDevice) {
      return FlipperDevice(
        id: device.id,
        name: device.name,
        link: FlipperLink.ble,
        source: device,
        rssi: device.rssi,
      );
    }
    if (device is DesktopUsbDiscoveredDevice) {
      return FlipperDevice(
        id: device.id,
        name: device.name,
        link: FlipperLink.usb,
        source: device,
        vendorId: device.vendorId,
        productId: device.productId,
        serialNumber: device.serialNumber,
      );
    }
    if (device is AndroidUsbDiscoveredDevice) {
      return FlipperDevice(
        id: device.id,
        name: device.name,
        link: FlipperLink.usb,
        source: device,
        vendorId: device.usbDevice.vid,
        productId: device.usbDevice.pid,
      );
    }
    throw UnsupportedError('Unsupported device: ${device.runtimeType}');
  }

  Future<_Transport> _openTransport(FlipperDevice device) {
    if (device.source is BleDiscoveredDevice) {
      return _blePlatform.openTransport(device.source as BleDiscoveredDevice);
    }
    if (device.source is UsbDiscoveredDevice) {
      return _usbPlatform.openTransport(device.source as UsbDiscoveredDevice);
    }
    throw UnsupportedError(
      'Unsupported device source: ${device.source.runtimeType}',
    );
  }

  void _rememberDevice(FlipperDevice device) {
    _devices['${device.link.name}:${device.id}'] = device;
    _emitDevices();
  }

  // Throttled: at most one event per window, plus a trailing event so the
  // final state always reaches listeners. `immediate` flushes right away
  // (scan finished, explicit refresh).
  void _emitDevices({bool immediate = false}) {
    if (immediate) {
      _devicesEmitTimer?.cancel();
      _devicesEmitTimer = null;
      _devicesEmitDirty = false;
      _emitDevicesNow();
      return;
    }
    if (_devicesEmitTimer != null) {
      _devicesEmitDirty = true;
      return;
    }
    _emitDevicesNow();
    _devicesEmitTimer = Timer(_devicesEmitWindow, () {
      _devicesEmitTimer = null;
      if (_devicesEmitDirty) {
        _devicesEmitDirty = false;
        _emitDevices();
      }
    });
  }

  void _emitDevicesNow() {
    if (_devicesCtrl.isClosed) return;
    final list = _devices.values.toList()
      ..sort((a, b) {
        final byLink = a.link.index.compareTo(b.link.index);
        if (byLink != 0) return byLink;
        return a.name.compareTo(b.name);
      });
    _devicesCtrl.add(List.unmodifiable(list));
  }

  // ── Session lifecycle ──────────────────────────────────────────────────────

  Future<FlipperDevice> connectById(String id, {FlipperLink? link}) async {
    FlipperDevice? device;
    for (final candidate in devices) {
      if (candidate.id != id) continue;
      if (link != null && candidate.link != link) continue;
      device = candidate;
      break;
    }
    if (device == null) {
      throw StateError('Device not found: $id');
    }
    return connect(device);
  }

  /// Connects to [device] and makes its session the active one. An already
  /// connected session is reused (an instant swap); other live sessions are
  /// kept connected and warm.
  Future<FlipperDevice> connect(FlipperDevice device) =>
      _serialized(() => _connectLocked(device));

  Future<FlipperDevice> _connectLocked(FlipperDevice device) async {
    final key = _deviceKey(device);
    final existing = _sessions[key];
    if (existing != null) {
      if (existing.isConnected || existing.isConnecting) {
        _activateLocked(existing);
        return existing.device;
      }
      _dropSessionLocked(existing);
    }
    final previous = _active;
    final session = _FlipperSession(this, device);
    _sessions[key] = session;
    _sessionWatches[session] = session._connectionCtrl.stream.listen(
      (_) => _emitSessions(),
    );
    // Active from the first moment of the attempt so the connecting phase is
    // visible on the public streams (and cancellable from the UI).
    _activateLocked(session);
    try {
      await session.establishLocked();
    } catch (error) {
      _dropSessionLocked(session);
      _activateLocked(
        (previous != null && previous.isConnected)
            ? previous
            : _mostRecentConnected(),
      );
      rethrow;
    }
    if (device.isUsb) _ensureUsbPresenceWatch();
    _emitSessions();
    return session.device;
  }

  /// Instantly reroutes all API calls and public streams to the live session
  /// of [device] — no radio work. Throws when the device holds no session.
  Future<void> activate(FlipperDevice device) =>
      activateById(device.id, link: device.link);

  Future<void> activateById(String id, {FlipperLink? link}) {
    return _serialized(() async {
      final session = _findSession(id, link: link);
      if (session == null || !(session.isConnected || session.isConnecting)) {
        throw StateError('Device not connected: $id');
      }
      _activateLocked(session);
    });
  }

  /// Disconnects the active session. When another session is still connected,
  /// the most recently used one becomes active.
  Future<void> disconnect() {
    // A connect attempt in flight holds the platform link and sits ahead of
    // this teardown in the lifecycle chain. Abort the platform connect up
    // front so the attempt unwinds now instead of blocking the user's
    // disconnect for the full connect timeout. Harmless when nothing is
    // connecting.
    _active?.abortConnectInFlight();
    return _serialized(() async {
      final session = _active;
      if (session == null) return;
      await session.teardownLocked('disconnect requested');
      _dropSessionLocked(session);
      _activateLocked(_mostRecentConnected());
    });
  }

  /// Disconnects one held session by device identity, active or warm.
  Future<void> disconnectDevice(String id, {FlipperLink? link}) {
    _findSession(id, link: link)?.abortConnectInFlight();
    return _serialized(() async {
      final session = _findSession(id, link: link);
      if (session == null) return;
      final wasActive = identical(_active, session);
      await session.teardownLocked('disconnect requested');
      _dropSessionLocked(session);
      if (wasActive) _activateLocked(_mostRecentConnected());
    });
  }

  Future<void> disconnectAll() {
    for (final session in _sessions.values) {
      session.abortConnectInFlight();
    }
    return _serialized(() async {
      final sessions = List<_FlipperSession>.from(_sessions.values);
      for (final session in sessions) {
        await session.teardownLocked('disconnect requested');
        _dropSessionLocked(session);
      }
      _activateLocked(null);
    });
  }

  String _deviceKey(FlipperDevice device) =>
      '${device.link.name}:${device.id}';

  _FlipperSession? _findSession(String id, {FlipperLink? link}) {
    for (final session in _sessions.values) {
      if (session.device.id != id) continue;
      if (link != null && session.device.link != link) continue;
      return session;
    }
    return null;
  }

  _FlipperSession? _mostRecentConnected() {
    _FlipperSession? best;
    for (final session in _sessions.values) {
      if (!session.isConnected) continue;
      if (best == null || session._activationStamp > best._activationStamp) {
        best = session;
      }
    }
    return best;
  }

  // Reroutes the public streams to [session] and re-announces its state.
  // Events of the previously piped session that were still queued for
  // delivery are dropped with the old pipes; the announced snapshot is the
  // authoritative truth consumers resync from.
  void _activateLocked(_FlipperSession? session) {
    if (identical(_active, session)) {
      _emitSessions();
      return;
    }
    _detachPipes();
    _active = session;
    if (session != null) {
      session._activationStamp = ++_activationSeq;
      _activePipes.addAll([
        session._modeCtrl.stream.listen((event) {
          if (!_modeCtrl.isClosed) _modeCtrl.add(event);
        }),
        session._connectionCtrl.stream.listen((event) {
          if (!_connectionCtrl.isClosed) _connectionCtrl.add(event);
        }),
        session._rawCtrl.stream.listen((event) {
          if (!_rawCtrl.isClosed) _rawCtrl.add(event);
        }),
        session._textCtrl.stream.listen((event) {
          if (!_textCtrl.isClosed) _textCtrl.add(event);
        }),
        session._messageCtrl.stream.listen((event) {
          if (!_messageCtrl.isClosed) _messageCtrl.add(event);
        }),
        session._broadcastCtrl.stream.listen((event) {
          if (!_broadcastCtrl.isClosed) _broadcastCtrl.add(event);
        }),
        session._errorCtrl.stream.listen((event) {
          if (!_errorCtrl.isClosed) _errorCtrl.add(event);
        }),
        session._deviceInfoCompleteCtrl.stream.listen((event) {
          if (!_deviceInfoCompleteCtrl.isClosed) {
            _deviceInfoCompleteCtrl.add(event);
          }
        }),
        session._deviceInfoWatchCtrl.stream.listen((event) {
          if (!_deviceInfoWatchCtrl.isClosed) _deviceInfoWatchCtrl.add(event);
        }),
        session._storageMutationCtrl.stream.listen((event) {
          if (!_storageMutationCtrl.isClosed) _storageMutationCtrl.add(event);
        }),
      ]);
    }
    _announceActiveState();
    _emitSessions();
  }

  void _detachPipes() {
    for (final pipe in _activePipes) {
      pipe.cancel();
    }
    _activePipes.clear();
  }

  void _announceActiveState() {
    final session = _active;
    final mode = session?._mode ?? FlipperMode.disconnected;
    if (!_modeCtrl.isClosed) _modeCtrl.add(mode);
    if (_connectionCtrl.isClosed) return;
    final connected = session?.isConnected ?? false;
    final connecting = session?.isConnecting ?? false;
    _connectionCtrl.add(
      FlipperConnectionState(
        mode: mode,
        device: (connected || connecting) ? session!.device : null,
        connected: connected,
        connecting: connecting,
      ),
    );
  }

  void _dropSessionLocked(_FlipperSession session) {
    _sessionWatches.remove(session)?.cancel();
    final key = _deviceKey(session.device);
    if (identical(_sessions[key], session)) {
      _sessions.remove(key);
    }
    if (identical(_active, session)) {
      _detachPipes();
      _active = null;
    }
    unawaited(session.dispose());
    _emitSessions();
  }

  // A session died terminally on its own (fault with reconnect exhausted or
  // disallowed). Runs off the session's recovery path; the microtask hop lets
  // the terminal disconnect event drain through the pipes before they are
  // detached.
  void _onSessionEnded(_FlipperSession session) {
    scheduleMicrotask(() {
      final key = _deviceKey(session.device);
      if (!identical(_sessions[key], session)) return;
      final wasActive = identical(_active, session);
      _dropSessionLocked(session);
      if (wasActive) _activateLocked(_mostRecentConnected());
    });
  }

  void _emitSessions() {
    if (_sessionsCtrl.isClosed) return;
    _sessionsCtrl.add(sessions);
  }

  // ── USB presence watch ─────────────────────────────────────────────────────

  // A live USB session must drop the moment the OS reports the port gone,
  // not only when the transport's own read loop eventually errors out — the
  // latter can lag for seconds after the cable is pulled. Started on the first
  // USB connect and torn down once no USB session remains.
  void _ensureUsbPresenceWatch() {
    _usbPresenceSub ??= _usbPlatform.usbEvents.listen(
      (_) => _pruneVanishedUsb(),
    );
  }

  void _maybeStopUsbPresenceWatch() {
    final hasUsb = _sessions.values.any(
      (s) => s.device.isUsb && (s.isConnected || s.isConnecting),
    );
    if (hasUsb) return;
    _usbPresenceSub?.cancel();
    _usbPresenceSub = null;
  }

  Future<void> _pruneVanishedUsb() async {
    final usbSessions = [
      for (final s in _sessions.values)
        if (s.device.isUsb && (s.isConnected || s.isConnecting)) s,
    ];
    if (usbSessions.isEmpty) {
      _maybeStopUsbPresenceWatch();
      return;
    }

    final Set<String> present;
    try {
      present = {for (final d in await _usbPlatform.loadDevices()) d.id};
    } catch (e) {
      Log.error('[FlipperClient] USB presence check failed: $e');
      return;
    }

    final vanished = [
      for (final s in usbSessions)
        if (!present.contains(s.device.id)) s,
    ];
    if (vanished.isEmpty) return;

    for (final session in vanished) {
      session.abortConnectInFlight();
    }
    await _serialized(() async {
      for (final session in vanished) {
        if (!identical(_sessions[_deviceKey(session.device)], session)) {
          continue;
        }
        Log.info(
          '[FlipperClient] USB ${session.device.id} removed; disconnecting',
        );
        final wasActive = identical(_active, session);
        await session.teardownLocked('usb removed');
        _dropSessionLocked(session);
        if (wasActive) _activateLocked(_mostRecentConnected());
      }
    });
    _maybeStopUsbPresenceWatch();
  }

  // Appends a lifecycle operation to the chain. The chain never breaks: a
  // failed operation surfaces its error to its own caller only.
  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _lifecycleChain.then((_) => op());
    _lifecycleChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  // ── RPC / CLI delegation to the active session ─────────────────────────────

  Future<void> switchToRpcMode() {
    final session = _active;
    if (session == null) {
      return Future.error(StateError('No active transport'));
    }
    return session.switchToRpcMode();
  }

  // Mode-restore entry point (UI lifecycle, e.g. a CLI page's dispose()).
  // Unlike the RPC senders, it is lenient: if the session is already gone
  // there is nothing to restore, so it returns quietly instead of throwing.
  // Callers fire it unawaited, where a thrown "No active transport" would
  // otherwise surface as an unhandled exception and crash the frame.
  Future<void> enterRpcMode() {
    final session = _active;
    if (session == null || session._transport == null) return Future.value();
    return session.switchToRpcMode();
  }

  Future<void> switchToCliMode() {
    final session = _active;
    if (session == null) {
      return Future.error(StateError('No device connected'));
    }
    return session.switchToCliMode();
  }

  Future<void> enterCliMode() => switchToCliMode();

  Future<String> executeCli(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final session = _active;
    if (session == null) {
      return Future.error(StateError('No active transport'));
    }
    return session.executeCli(command, timeout: timeout);
  }

  Future<String> executeCliCommand(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    return executeCli(command, timeout: timeout);
  }

  Future<void> writeCliText(String text) =>
      _requireActiveSession().writeCliText(text);

  Future<void> writeCliBytes(Uint8List bytes) =>
      _requireActiveSession().writeCliBytes(bytes);

  Future<void> sendRpc(
    Main message, {
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
    Duration sendTimeout = const Duration(seconds: 30),
  }) {
    return _requireActiveSession().sendRpc(
      message,
      priority: priority,
      sendTimeout: sendTimeout,
    );
  }

  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
    void Function(Main frame)? onFrame,
    bool retainFrames = true,
    bool interleavable = false,
  }) {
    return _requireActiveSession().callRpcFrames(
      request,
      timeout: timeout,
      priority: priority,
      onFrame: onFrame,
      retainFrames: retainFrames,
      interleavable: interleavable,
    );
  }

  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) body, {
    Duration timeout = const Duration(seconds: 60),
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
  }) {
    return _requireActiveSession().callRpcFramesMulti(
      body,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<T>> callRpc<T extends $pb.GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
    void Function(Main frame)? onFrame,
  }) async {
    final frames = await callRpcFrames(
      request,
      timeout: timeout,
      priority: priority,
      onFrame: onFrame,
    );
    final items = <T>[];
    for (final frame in frames) {
      final item = pick(frame);
      if (item != null) {
        items.add(item);
      }
    }
    return FlipperRpcBatch<T>(
      commandId: request.commandId,
      request: request,
      frames: frames,
      items: items,
    );
  }

  Stream<T> select<T extends $pb.GeneratedMessage>(
    T? Function(Main frame) pick,
  ) {
    return messageStream.transform(
      StreamTransformer<Main, T>.fromHandlers(
        handleData: (frame, sink) {
          final selected = pick(frame);
          if (selected != null) {
            sink.add(selected);
          }
        },
      ),
    );
  }

  // ── Link-drop retry support (used by storage transfers) ───────────────────

  // True for failures caused by the link dying (as opposed to an RPC-level
  // error from the firmware): these are the ones an automatic reconnect can
  // make whole again.
  bool _isLinkDropError(Object error) {
    if (error is FlipperTransportError) return true;
    if (error is StateError) {
      final message = error.message;
      return message.startsWith('Disconnected') ||
          message.startsWith('Request dropped') ||
          message.contains('Transport closed') ||
          message.contains('No active transport');
    }
    return false;
  }

  // Waits until the client is back in RPC mode over a live transport (e.g.
  // after an automatic reconnect), up to [timeout]. The transport check
  // matters: right after a fault the mode still reads `rpc` for a moment while
  // the recovery operation is queued, and trusting it would burn a retry on
  // the dead session. A timeout is a result, not an exception.
  Future<bool> _waitForRpcSession(Duration timeout) async {
    bool healthy() =>
        _mode == FlipperMode.rpc && (_transport?.isActive ?? false);

    if (healthy()) return true;
    final restored = Completer<bool>();
    final timer = Timer(timeout, () {
      if (!restored.isCompleted) restored.complete(false);
    });
    final modeSub = modeStream.listen((mode) {
      if (mode == FlipperMode.rpc && healthy() && !restored.isCompleted) {
        restored.complete(true);
      }
    });
    // A terminal disconnect (no reconnect in progress) ends the wait early
    // instead of burning the whole timeout.
    final connSub = connectionStream.listen((state) {
      if (!state.connected && !state.reconnecting && !restored.isCompleted) {
        restored.complete(false);
      }
    });
    if (healthy() && !restored.isCompleted) {
      restored.complete(true);
    }
    final result = await restored.future;
    timer.cancel();
    await modeSub.cancel();
    await connSub.cancel();
    return result;
  }

  // ── Shutdown ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _usbPresenceSub?.cancel();
    _usbPresenceSub = null;
    await disconnectAll();
    await stopScan();
    _devicesEmitTimer?.cancel();
    _devicesEmitTimer = null;
    await _devicesCtrl.close();
    await _connectionCtrl.close();
    await _modeCtrl.close();
    await _rawCtrl.close();
    await _textCtrl.close();
    await _messageCtrl.close();
    await _broadcastCtrl.close();
    await _errorCtrl.close();
    await _deviceInfoCompleteCtrl.close();
    await _deviceInfoWatchCtrl.close();
    await _storageMutationCtrl.close();
    await _sessionsCtrl.close();
  }
}

// Coarse per-session connection lifecycle. `connecting` covers the whole
// connect window (transport not yet committed); `connected` mirrors
// `_transport != null`. See _FlipperSession._linkPhase.
enum _LinkPhase { disconnected, connecting, connected }
