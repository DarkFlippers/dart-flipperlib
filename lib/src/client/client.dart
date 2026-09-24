import 'dart:async';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart' as $pb;
import 'package:universal_ble/universal_ble.dart' as uble;

import '../../protobuf.dart';
import '../common/log.dart';
import '../model/device.dart';
import '../model/discovered.dart';
import '../model/enums.dart';
import '../model/exceptions.dart';
import '../session/session.dart';
import '../transport/ble/ble.dart';
import '../transport/transport.dart';
import '../transport/usb/usb.dart';

// Zone key for the session the running task is bound to.
final Object _taskBindingKey = Object();

class _TaskBinding {
  const _TaskBinding(this.session);

  // Null when a task unbound itself on purpose: work the user drives follows
  // the device on screen even when it started from inside a bound task.
  final FlipperSession? session;
}

/// A pass's claim on the Flipper that was in scope when it started.
///
/// Work outlives devices. A walk, an upload, a firmware transfer or a
/// catalogue request runs for as long as it runs, and warm sessions let the
/// user swap Flippers without the link ever dropping - `isConnected` stays true
/// right across the switch, so it cannot be the test. Take a token before the
/// work and check [isStale] after each await, before writing anything the
/// switch invalidated.
///
/// This answers what to keep, not where to send. Which Flipper a request
/// reaches is [FlipperClient.runTask]'s job, and the two are not
/// interchangeable: a transfer that finishes on the previous device is correct
/// and complete *there*, while what the app records about it is still dropped,
/// because the screen describes a different one now.
class DeviceToken {
  const DeviceToken._(this._client, this._revision);

  final FlipperClient _client;
  final int _revision;

  bool get isCurrent => _revision == _client._deviceRevision;

  bool get isStale => !isCurrent;

  @override
  bool operator ==(Object other) =>
      other is DeviceToken &&
      identical(other._client, _client) &&
      other._revision == _revision;

  @override
  int get hashCode => Object.hash(identityHashCode(_client), _revision);
}

/// The session a task talks to, held so it can go on talking to it after the
/// user has switched devices.
///
/// [FlipperClient.runTask] covers work that fits in one async body. This is for
/// work that outlives one - a screen stream, a virtual display - where the stop
/// command has to reach the Flipper the stream runs on rather than the one that
/// happens to be on screen when the page closes.
class FlipperSessionBinding {
  const FlipperSessionBinding._(this._session);

  final FlipperSession? _session;

  FlipperDevice? get device => _session?.device;

  /// False once the bound link is gone. Requests made under a dead binding
  /// fail; they never retarget the device that is active now.
  bool get isAlive => _session?.isConnected ?? false;

  /// Runs [body] with every request it makes bound to this session.
  T run<T>(T Function() body) =>
      runZoned(body, zoneValues: {_taskBindingKey: _TaskBinding(_session)});
}

// Facade over N FlipperSession objects (one per physical link) plus device
// discovery. Exactly one session is "active": the public streams and the
// device-state getters route to it, and so does any request that is not part
// of a bound task. The other sessions stay connected and warm — activate()
// swaps the routing instantly, with zero radio work, which is exactly why work
// that spans a switch has to hold the session it started against instead of
// asking for the active one again.
class FlipperClient {
  static const String bleServiceUuid = flipperBleServiceUuid;
  static const String bleRxUuid = flipperBleRxUuid;
  static const String bleTxUuid = flipperBleTxUuid;
  static const String cliPrompt = '\r\n\r\n>: ';
  static const String startRpcSession = 'start_rpc_session\r';
  static const int maxRxParseErrorStreak = 3;
  static const Duration quickDropWindow = Duration(seconds: 30);
  static const int maxQuickDropStreak = 2;
  static const Duration reconnectSettle = Duration(milliseconds: 600);
  // Gap between tearing a scan down and claiming the link. The platform frees
  // the radio asynchronously, and a connect issued in the same instant loses
  // slots to the still-winding-down scan — on Apple that surfaces as
  // CBErrorEncryptionTimedOut mid-pairing.
  static const Duration radioSettle = Duration(milliseconds: 300);
  // How long connectBleAddress waits before giving the radio back. Matches
  // flipper-android's own bound for a connect to a remembered device.
  static const Duration bleAddressConnectTimeout = Duration(seconds: 30);
  // How long connectBleAddress waits for the platform's BLE stack to come up
  // before dialling. A scan checks the adapter state itself and simply reports
  // nothing while it is down; a direct connect has no such step, and a cold
  // CoreBluetooth central answers every address with "unknown deviceId" until
  // it reaches poweredOn - which is exactly the first second after launch.
  static const Duration bleAvailabilityWait = Duration(seconds: 5);

  final _devicesCtrl = StreamController<List<FlipperDevice>>.broadcast();
  final connectionCtrl = StreamController<FlipperConnectionState>.broadcast();
  final rawCtrl = StreamController<List<int>>.broadcast();
  final textCtrl = StreamController<String>.broadcast();
  final messageCtrl = StreamController<Main>.broadcast();
  final broadcastCtrl = StreamController<Main>.broadcast();
  final errorCtrl = StreamController<FlipperRpcException>.broadcast();
  final deviceInfoCompleteCtrl =
      StreamController<Map<String, String>>.broadcast();
  final deviceInfoWatchCtrl = StreamController<Map<String, String>>.broadcast();
  final storageMutationCtrl = StreamController<void>.broadcast();
  final _sessionsCtrl = StreamController<List<FlipperSessionInfo>>.broadcast();
  final _heardCtrl = StreamController<FlipperDevice>.broadcast();

  final Map<String, FlipperDevice> _devices = {};
  final Map<String, FlipperSession> _sessions = {};
  final Map<FlipperSession, StreamSubscription<FlipperConnectionState>>
  _sessionWatches = {};
  final List<StreamSubscription<dynamic>> _activePipes = [];
  FlipperSession? _active;
  int _activationSeq = 0;

  String? _scopedDeviceId;
  int _deviceRevision = 0;
  // What the last state put on connectionCtrl said the scope was. The one piece
  // of "have I noticed yet" bookkeeping in the app, kept here so that no
  // listener has to keep its own.
  int _announcedRevision = 0;
  FlipperMode _announcedMode = FlipperMode.disconnected;

  Future<void> _lifecycleChain = Future.value();
  bool autoReconnect = true;
  static const int maxSessions = 2;

  StreamSubscription<void>? _usbPresenceSub;

  bool _scanning = false;
  // Bumped by stopScan: a scan already queued on the lifecycle chain but not
  // yet started sees a stale epoch and turns into a no-op instead of grabbing
  // the radio right after the connect that cancelled it.
  int _scanEpoch = 0;
  // The running scan phase, awaited by stopScan so callers observe the radio
  // as free only once the platform scan is actually torn down.
  Future<void>? _scanInFlight;
  // Runs from the moment the last scan released the radio. awaitRadioSettled
  // measures the settle from here, so the pause applies whether the scan ended
  // on its own timeout or was preempted by the connect claiming the link.
  final Stopwatch _radioFreedAt = Stopwatch();
  Completer<void>? _scanPhaseInterrupt;
  static const Duration _scanGraceWindow = Duration(seconds: 5);
  Timer? _scanGraceTimer;
  static const Duration _devicesEmitWindow = Duration(milliseconds: 200);
  Timer? _devicesEmitTimer;
  bool _devicesEmitDirty = false;

  static const Set<Main_Content> heavyStorageContent = {
    Main_Content.storageWriteRequest,
    Main_Content.storageReadRequest,
    Main_Content.storageDeleteRequest,
  };

  static const Set<Main_Content> mutatingStorageContent = {
    Main_Content.storageWriteRequest,
    Main_Content.storageDeleteRequest,
  };

  // ── Public streams (piped from the active session) ────────────────────────

  Stream<List<FlipperDevice>> get devicesStream => _devicesCtrl.stream;

  Stream<FlipperConnectionState> get connectionStream => connectionCtrl.stream;

  Stream<List<int>> get rawBytesStream => rawCtrl.stream;

  Stream<String> get textStream => textCtrl.stream;

  Stream<Main> get messageStream => messageCtrl.stream;

  Stream<Main> get broadcastStream => broadcastCtrl.stream;

  Stream<Main> get notificationStream => broadcastCtrl.stream;

  Stream<FlipperRpcException> get errorStream => errorCtrl.stream;

  Stream<void> get storageMutations => storageMutationCtrl.stream;

  Stream<void> get usbEvents => usbPlatform.usbEvents;

  Stream<Map<String, String>> get deviceInfoStream =>
      deviceInfoCompleteCtrl.stream;

  /// Broadcast stream of device-info patches.
  ///
  /// Each event is a partial [Map<String, String>] — subscribers merge it into
  /// their own state. Subscribing has no side-effects.
  Stream<Map<String, String>> get deviceInfoUpdates =>
      deviceInfoWatchCtrl.stream;

  /// Snapshot stream of every held link (active and warm). Emits on connect,
  /// disconnect, activation swap and any session state change.
  Stream<List<FlipperSessionInfo>> get sessionsStream => _sessionsCtrl.stream;

  /// Every BLE device the radio actually heard from: an advertisement during
  /// a scan, or a device the system reported as connected. Unlike
  /// [devicesStream], which carries the accumulated list, each event here is
  /// fresh evidence that the device is reachable right now.
  Stream<FlipperDevice> get bleHeard => _heardCtrl.stream;

  // ── Facade state ───────────────────────────────────────────────────────────

  List<FlipperDevice> get devices =>
      List.unmodifiable(_devices.values.toList());

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

  FlipperSession? get _connectingSession {
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

  FlipperMode get mode => _active?.mode ?? FlipperMode.disconnected;

  bool get isConnected => _active?.isConnected ?? false;

  /// The link is up and speaking RPC - the precondition for every device call
  /// the app makes that is not raw CLI text.
  ///
  /// Here rather than assembled by each caller: a session in CLI mode is still
  /// connected and still refuses every RPC, so `isConnected` alone is the wrong
  /// question and open-coding the right one in each place is how some callers
  /// end up asking the wrong one.
  bool get isRpcReady => isConnected && mode == FlipperMode.rpc;

  /// The link is up and in CLI mode, ready for raw text.
  bool get isCliReady => isConnected && mode == FlipperMode.cli;

  bool get isScanning => _scanning;

  Transport? get transport => _currentSession?.transport;

  bool get storageBusy => _currentSession?.storageBusy ?? false;

  /// True while an open CLI channel holds the session requests would reach:
  /// RPC is refused until the channel closes.
  bool get cliHeld => _currentSession?.cliHeld ?? false;

  Map<String, String> get deviceInfoCache =>
      _currentSession?.deviceInfoCache ?? const {};

  bool get deviceInfoFetched => _currentSession?.deviceInfoFetched ?? false;

  void publishDeviceInfoPatch(Map<String, String> patch) {
    _currentSession?.publishDeviceInfoPatch(patch);
  }

  Map<String, String> get deviceInfoWatchSnapshot =>
      _currentSession?.deviceInfoWatchSnapshot ?? const {};

  String? getName() => _currentSession?.getName();

  String? getNameOf(FlipperDevice device) =>
      _findSession(device.id, link: device.link)?.getName();

  Future<String> awaitName() {
    final session = _currentSession;
    if (session == null) {
      return Future.error(
        StateError('Cannot fetch device info: no active transport'),
      );
    }
    return session.awaitName();
  }

  Future<Map<String, String>> awaitDeviceInfo() {
    final session = _currentSession;
    if (session == null) {
      return Future.error(
        StateError('Cannot fetch device info: no active transport'),
      );
    }
    return session.awaitDeviceInfo();
  }

  int nextCommandId() => _requireCurrentSession().nextCommandId();

  // The task's binding, or nothing when the caller is not running inside one.
  /// Which Flipper the app's device-scoped state describes right now.
  ///
  /// Everything an app keeps about a device - what is installed on it, what its
  /// firmware is, what a page is showing - belongs to one Flipper, and a token
  /// taken from here says whether it still does. See [DeviceToken].
  DeviceToken get deviceToken => DeviceToken._(this, _deviceRevision);

  String? get scopedDeviceId => _scopedDeviceId;

  // Moving to a different Flipper stales every token handed out so far.
  //
  // Losing the link is not a move: the same device coming back leaves the work
  // that was in flight valid, and so does a swap between two links to one
  // Flipper - same storage, same apps, same firmware. Only the identity counts.
  // Attaches the client's verdict to a state on its way out: what happened, and
  // which Flipper it is about. A session cannot work the first out - it does not
  // know what the previous event said - so every state is stamped here, whether
  // it was raised by the facade or piped up from a session.
  FlipperConnectionState _stampEvent(FlipperConnectionState state) {
    final deviceMoved = _deviceRevision != _announcedRevision;
    final previousMode = _announcedMode;
    _announcedRevision = _deviceRevision;
    _announcedMode = state.mode;

    final FlipperConnectionEvent event;
    if (!state.connected) {
      event = state.connecting
          ? FlipperConnectionEvent.connecting
          : FlipperConnectionEvent.disconnected;
    } else if (deviceMoved) {
      // Ranked above a mode change because it is the larger statement: a
      // listener told the Flipper changed has nothing left to salvage from what
      // it knew, whichever protocol the new one came up in.
      event = FlipperConnectionEvent.deviceChanged;
    } else if (state.mode != previousMode &&
        previousMode != FlipperMode.disconnected) {
      // Between working modes only. Coming up out of nothing is a connect, not
      // a protocol switch, and calling it one would hide the connect from every
      // listener waiting for it.
      event = FlipperConnectionEvent.modeChanged;
    } else {
      event = FlipperConnectionEvent.connected;
    }
    return state.stamp(event, _deviceRevision);
  }

  void _moveScope(FlipperSession? session) {
    final id = session?.device.id;
    if (id == null || id == _scopedDeviceId) return;
    _scopedDeviceId = id;
    _deviceRevision++;
  }

  FlipperSession? get _boundSession {
    final binding = Zone.current[_taskBindingKey];
    return binding is _TaskBinding ? binding.session : null;
  }

  /// The session a request of [priority] issued right here should reach.
  ///
  /// [FlipperRequestPriority.foreground] always means the active session. Those
  /// are the readings that exist to be shown - voltage, current, device info -
  /// and they follow whichever Flipper the user is looking at, because being
  /// looked at is their whole purpose. They are never part of a task, so this
  /// takes nothing away from one.
  ///
  /// Everything else goes to the running task's binding, falling back to the
  /// active session when there is no task. A task keeps the link it bound for
  /// the work itself and for the `rightNow` control that belongs to it - the
  /// ping pacing an upload, the delete of its half-written file, the stop that
  /// puts a screen stream out. A binding whose link is gone fails the request
  /// rather than falling back: retargeting is the bug this exists to stop.
  FlipperSession? _sessionFor(FlipperRequestPriority priority) {
    if (priority == FlipperRequestPriority.foreground) return _active;
    return _boundSession ?? _active;
  }

  FlipperSession? get _currentSession => _boundSession ?? _active;

  FlipperSession _requireSessionFor(FlipperRequestPriority priority) {
    final session = _sessionFor(priority);
    if (session == null) {
      throw StateError('No active transport');
    }
    return session;
  }

  FlipperSession _requireCurrentSession() {
    final session = _currentSession;
    if (session == null) {
      throw StateError('No active transport');
    }
    return session;
  }

  /// Binds the session this task is talking to, for work that outlives one
  /// async body and has to go on reaching the same Flipper.
  FlipperSessionBinding bindCurrentSession() =>
      FlipperSessionBinding._(_currentSession);

  /// Runs [body] as one task.
  ///
  /// [FlipperRequestPriority.background] binds the session in play right now:
  /// a scan, an install or a manifest refresh goes on talking to the Flipper it
  /// started against, whatever the user plugs in meanwhile. Every other
  /// priority unbinds, so work the user drives follows the device on screen,
  /// which is what a tap means.
  ///
  /// Requests inside [body] inherit the binding whatever their own priority is:
  /// the priority orders the queue, the task picks the device. Nesting follows
  /// the same rule, so a background task started inside another one stays on
  /// the outer task's link rather than jumping to the active session.
  Future<T> runTask<T>(
    FlipperRequestPriority priority,
    Future<T> Function() body,
  ) {
    final binding = priority == FlipperRequestPriority.background
        ? FlipperSessionBinding._(_currentSession)
        : const FlipperSessionBinding._(null);
    return binding.run(body);
  }

  // ── Discovery ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    await blePlatform.requestPermissions();
  }

  Future<List<FlipperDevice>> refreshDevices({
    Duration bleTimeout = const Duration(seconds: 10),
  }) {
    final epoch = _scanEpoch;
    return _enqueue(() => _refreshDevicesLocked(epoch, bleTimeout));
  }

  Future<List<FlipperDevice>> _refreshDevicesLocked(
    int epoch,
    Duration bleTimeout,
  ) async {
    _devices.clear();
    for (final session in _sessions.values) {
      if (session.isConnected || session.isConnecting) {
        _rememberDevice(session.device);
      }
    }
    await _loadUsbDevices();
    _emitDevices(immediate: true);
    await _scanPhase(epoch, bleTimeout);
    return devices;
  }

  Future<void> scanBle({Duration timeout = const Duration(seconds: 10)}) {
    final epoch = _scanEpoch;
    return _enqueue(() => _scanPhase(epoch, timeout));
  }

  // Publishes the running phase for stopScan and drops a scan whose epoch was
  // cancelled while it waited its turn on the chain.
  Future<void> _scanPhase(int epoch, Duration timeout) {
    if (epoch != _scanEpoch) {
      Log.info('[BLE] scan cancelled before start');
      return Future<void>.value();
    }
    final phase = _scanBleLocked(_scanEpoch, timeout);
    _scanInFlight = phase;
    return phase.whenComplete(() {
      if (identical(_scanInFlight, phase)) _scanInFlight = null;
    });
  }

  Future<void> _scanBleLocked(int epoch, Duration timeout) async {
    _scanning = true;
    var heldRadio = false;

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

      uble.UniversalBle.onScanResult = (device) {
        final discovered = BleDiscoveredDevice(device);
        if (Log.debugOn) {
          Log.debug(
            '[BLE] scan result id=${discovered.id} name=${discovered.name} '
            'rssi=${discovered.rssi} services=${device.services}',
          );
        }
        final heard = _fromDiscovered(discovered);
        _rememberDevice(heard);
        _heard(heard);
        if (_hasFilteredBleDevice()) _armScanGrace();
      };

      // Single phase scanning every advertising device: Flipper identification
      // is name/service based (includeDevice), so the UI filter can also
      // reveal non-Flipper devices on demand.
      Log.info('[BLE] scan started');
      await uble.UniversalBle.startScan(
        platformConfig: uble.PlatformConfig(
          android: uble.AndroidOptions(
            scanMode: uble.AndroidScanMode.lowLatency,
            matchMode: uble.AndroidScanMatchMode.aggressive,
            numOfMatches: uble.AndroidScanNumOfMatches.max,
          ),
        ),
      );
      heldRadio = true;
      await _loadKnownBleDevices();
      try {
        final interrupt = _scanPhaseInterrupt = Completer<void>();
        // stopScan may have landed while the radio was still starting up, with
        // no completer to fire yet: the epoch carries that cancellation here so
        // the phase does not sit out its full timeout.
        if (epoch != _scanEpoch) fireOnce(interrupt);
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
      if (heldRadio) {
        _radioFreedAt
          ..reset()
          ..start();
      }
      _emitDevices(immediate: true);
    }
  }

  void _heard(FlipperDevice device) {
    if (!_heardCtrl.isClosed) _heardCtrl.add(device);
  }

  /// Ends scanning: cancels scans still queued behind the lifecycle chain and
  /// waits for a running phase to actually release the radio.
  Future<void> stopScan() async {
    _preemptScans();
    await _scanInFlight;
  }

  /// Waits out [radioSettle] from the moment the last scan released the radio.
  /// Returns immediately when no scan has run since the last settle.
  Future<void> awaitRadioSettled() async {
    if (!_radioFreedAt.isRunning) return;
    final remaining = radioSettle - _radioFreedAt.elapsed;
    _radioFreedAt
      ..stop()
      ..reset();
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
  }

  // Collapses the waiting part of a running scan and invalidates any scan still
  // queued on the chain, so whoever asked for the radio next gets it instead of
  // sitting through a scan timeout.
  void _preemptScans() {
    _scanEpoch++;
    _interruptScanPhase();
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
    fireOnce(interrupt);
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
    for (final device in await blePlatform.loadKnownDevices()) {
      final known = _fromDiscovered(device);
      _rememberDevice(known);
      _heard(known);
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
    final result = await usbPlatform.loadDevices();
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
      return blePlatform.includeDevice(source);
    }
    if (source is UsbDiscoveredDevice) {
      return usbPlatform.includeDevice(device);
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

  Future<Transport> openTransport(FlipperDevice device) {
    if (device.source is BleDiscoveredDevice) {
      return blePlatform.openTransport(device.source as BleDiscoveredDevice);
    }
    if (device.source is UsbDiscoveredDevice) {
      return usbPlatform.openTransport(device.source as UsbDiscoveredDevice);
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

  /// Connects straight to a BLE device by its platform address, with no scan.
  ///
  /// Discovery is pure overhead for an address the caller already knows: every
  /// platform resolves it on its own (Android `getRemoteDevice`, Apple
  /// `retrievePeripherals`), so the link opens from the address alone. The
  /// address is whatever the platform used as an id at discovery time - a MAC
  /// on Android / Linux / Windows, an opaque peer UUID on iOS / macOS. [name]
  /// is cosmetic, carried only until the device reports its own.
  ///
  /// A device already in [devices] is reused as-is, so an address that holds a
  /// live session swaps to it instantly instead of reconnecting.
  ///
  /// Unlike a connect to a scanned device, this one is bounded by [timeout]:
  /// a remembered device is already bonded, so the attempt cannot be sitting
  /// in a PIN prompt, and an address that is out of range would otherwise hold
  /// the client in its connecting state for the platform's own 60 s.
  Future<FlipperDevice> connectBleAddress(
    String address, {
    String? name,
    Duration timeout = bleAddressConnectTimeout,
  }) async {
    final known = _devices['${FlipperLink.ble.name}:$address'];
    final device =
        known ??
        _fromDiscovered(
          BleDiscoveredDevice(uble.BleDevice(deviceId: address, name: name)),
        );
    await _awaitBleAvailable(bleAvailabilityWait);
    try {
      final connected = await connect(device).timeout(timeout);
      _rememberDevice(connected);
      return connected;
    } on TimeoutException {
      await disconnectDevice(address, link: FlipperLink.ble);
      throw FlipperTransportError(
        'BLE connect to $address timed out after ${timeout.inSeconds}s',
      );
    }
  }

  Future<void> _awaitBleAvailable(Duration timeout) async {
    try {
      final state = await uble.UniversalBle.getBluetoothAvailabilityState();
      if (state == uble.AvailabilityState.poweredOn) return;
      Log.info('[BLE] adapter is $state; waiting for it to power on');
      await uble.UniversalBle.availabilityStream
          .firstWhere((s) => s == uble.AvailabilityState.poweredOn)
          .timeout(timeout);
      Log.info('[BLE] adapter powered on');
    } catch (e) {
      // Falling through on purpose: the connect below is what reports an
      // adapter that is off or unauthorised, with the platform's own error
      // for the UI to classify.
      Log.info('[BLE] adapter did not report ready: $e');
    }
  }

  /// Opens the link to [device] and makes its session the active one. An
  /// already connected session is reused (an instant swap); other live
  /// sessions are kept connected and warm.
  ///
  /// The link alone: the session comes up in the transport's own mode (USB in
  /// CLI, BLE in RPC) and nothing is switched here. [switchToRpcMode] and
  /// [switchToCliMode] are the two moves, each a no-op when already there, and
  /// every RPC sender makes the first one on its own before its request.
  Future<FlipperDevice> connect(FlipperDevice device) =>
      serialized(() async => (await _openLocked(device)).device);

  Future<FlipperSession> _openLocked(
    FlipperDevice device, {
    bool activate = true,
  }) async {
    final key = _deviceKey(device);
    final existing = _sessions[key];
    if (existing != null) {
      if (existing.isConnected || existing.isConnecting) {
        if (activate) _activateLocked(existing);
        return existing;
      }
      _dropSessionLocked(existing);
    }
    if (_sessions.length >= maxSessions) {
      throw StateError(
        'Only $maxSessions links can be held at once; disconnect one first',
      );
    }
    final previous = _active;
    final session = FlipperSession(this, device);
    _sessions[key] = session;
    _sessionWatches[session] = session.connectionCtrl.stream.listen(
      (_) => _emitSessions(),
    );
    // Active from the first moment of the attempt so the connecting phase is
    // visible on the public streams (and cancellable from the UI). A caller
    // that asked to keep the current session in front only gets that while it
    // is actually connected; with nothing in front, the new link takes it.
    final takesFront = activate || previous == null || !previous.isConnected;
    if (takesFront) _activateLocked(session);
    try {
      await session.establishLocked();
    } catch (error) {
      _dropSessionLocked(session);
      if (takesFront) {
        _activateLocked(
          (previous != null && previous.isConnected)
              ? previous
              : _mostRecentConnected(),
        );
      }
      rethrow;
    }
    if (device.isUsb) _ensureUsbPresenceWatch();
    _emitSessions();
    return session;
  }

  /// The one way into the firmware CLI of [device] (USB only).
  ///
  /// Whatever state the link is in, the channel comes back on a session that
  /// is in CLI mode and held there: no link yet opens one; a session speaking
  /// RPC is switched (the firmware has no RPC-to-CLI move, so that re-opens
  /// the link); a session already in CLI is left exactly as it is. While the
  /// channel is open, RPC on that session is refused with
  /// [FlipperCliBusyError]; closing it hands the session back, to RPC by
  /// default.
  ///
  /// A session that is already active stays active. When another device is
  /// active and connected, it keeps the front and the CLI session runs warm
  /// beside it, so the rest of the app carries on over the other link.
  Future<FlipperCliChannel> openCli(FlipperDevice device) {
    if (!device.isUsb) {
      return Future.error(
        FlipperUnsupportedModeError('CLI mode is only available over USB'),
      );
    }
    return serialized(() async {
      final held = _sessions[_deviceKey(device)];
      final fresh = held == null || !(held.isConnected || held.isConnecting);
      final session = await _openLocked(device, activate: false);
      final backlog = StringBuffer();
      final tap = session.textCtrl.stream.listen(backlog.write);
      session.cliHeld = true;
      try {
        if (fresh) {
          await session.ensureCliPromptLocked();
        } else if (session.mode != FlipperMode.cli) {
          await session.switchToCliLocked();
        }
      } catch (error) {
        session.cliHeld = false;
        await tap.cancel();
        rethrow;
      }
      final channel = FlipperCliChannel._(this, session, backlog.toString());
      await tap.cancel();
      _emitSessions();
      return channel;
    });
  }

  bool isCliOpen(FlipperDevice device) =>
      _sessions[_deviceKey(device)]?.mode == FlipperMode.cli;

  /// Instantly reroutes all API calls and public streams to the live session
  /// of the device — no radio work. Throws when it holds no session.
  Future<void> activateById(String id, {FlipperLink? link}) {
    return serialized(() async {
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
    return serialized(() async {
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
    return serialized(() async {
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
    return serialized(() async {
      final sessions = List<FlipperSession>.from(_sessions.values);
      for (final session in sessions) {
        await session.teardownLocked('disconnect requested');
        _dropSessionLocked(session);
      }
      _activateLocked(null);
    });
  }

  String _deviceKey(FlipperDevice device) => '${device.link.name}:${device.id}';

  FlipperSession? _findSession(String id, {FlipperLink? link}) {
    for (final session in _sessions.values) {
      if (session.device.id != id) continue;
      if (link != null && session.device.link != link) continue;
      return session;
    }
    return null;
  }

  FlipperSession? _mostRecentConnected() {
    FlipperSession? best;
    for (final session in _sessions.values) {
      if (!session.isConnected) continue;
      if (best == null || session.activationStamp > best.activationStamp) {
        best = session;
      }
    }
    return best;
  }

  // Reroutes the public streams to [session] and re-announces its state.
  // Events of the previously piped session that were still queued for
  // delivery are dropped with the old pipes; the announced snapshot is the
  // authoritative truth consumers resync from.
  void _activateLocked(FlipperSession? session) {
    if (identical(_active, session)) {
      _emitSessions();
      return;
    }
    _detachPipes();
    _active = session;
    _moveScope(session);
    if (session != null) {
      session.activationStamp = ++_activationSeq;
      _activePipes.addAll([
        session.connectionCtrl.stream.listen((event) {
          if (!connectionCtrl.isClosed) {
            connectionCtrl.add(_stampEvent(event));
          }
        }),
        session.rawCtrl.stream.listen((event) {
          if (!rawCtrl.isClosed) rawCtrl.add(event);
        }),
        session.textCtrl.stream.listen((event) {
          if (!textCtrl.isClosed) textCtrl.add(event);
        }),
        session.messageCtrl.stream.listen((event) {
          if (!messageCtrl.isClosed) messageCtrl.add(event);
        }),
        session.broadcastCtrl.stream.listen((event) {
          if (!broadcastCtrl.isClosed) broadcastCtrl.add(event);
        }),
        session.errorCtrl.stream.listen((event) {
          if (!errorCtrl.isClosed) errorCtrl.add(event);
        }),
        session.deviceInfoCompleteCtrl.stream.listen((event) {
          if (!deviceInfoCompleteCtrl.isClosed) {
            deviceInfoCompleteCtrl.add(event);
          }
        }),
        session.deviceInfoWatchCtrl.stream.listen((event) {
          if (!deviceInfoWatchCtrl.isClosed) deviceInfoWatchCtrl.add(event);
        }),
        session.storageMutationCtrl.stream.listen((event) {
          if (!storageMutationCtrl.isClosed) storageMutationCtrl.add(event);
        }),
      ]);
    }
    _announceActiveState();
    _emitSessions();
  }

  void _detachPipes() {
    for (final pipe in _activePipes) {
      unawaited(pipe.cancel());
    }
    _activePipes.clear();
  }

  void _announceActiveState() {
    final session = _active;
    final mode = session?.mode ?? FlipperMode.disconnected;
    if (connectionCtrl.isClosed) return;
    final connected = session?.isConnected ?? false;
    final connecting = session?.isConnecting ?? false;
    connectionCtrl.add(
      _stampEvent(
        FlipperConnectionState(
          mode: mode,
          device: (connected || connecting) ? session!.device : null,
          connected: connected,
          connecting: connecting,
        ),
      ),
    );
  }

  void _dropSessionLocked(FlipperSession session) {
    unawaited(_sessionWatches.remove(session)?.cancel());
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
  void onSessionEnded(FlipperSession session) {
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
    _usbPresenceSub ??= usbPlatform.usbEvents.listen(
      (_) => _pruneVanishedUsb(),
    );
  }

  void _maybeStopUsbPresenceWatch() {
    final hasUsb = _sessions.values.any(
      (s) => s.device.isUsb && (s.isConnected || s.isConnecting),
    );
    if (hasUsb) return;
    unawaited(_usbPresenceSub?.cancel());
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
      present = {for (final d in await usbPlatform.loadDevices()) d.id};
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
    await serialized(() async {
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

  // Appends a lifecycle operation to the chain. Scanning runs on the same
  // chain, so a scan phase and a connect can never overlap on the radio; the
  // waiting part of a scan is collapsed up front so the queued operation does
  // not sit behind the full scan timeout.
  Future<T> serialized<T>(Future<T> Function() op) {
    _preemptScans();
    return _enqueue(op);
  }

  // Chain append without the scan preemption — scans enqueue through this so
  // they do not cut their own phase short. The chain never breaks: a failed
  // operation surfaces its error to its own caller only.
  Future<T> _enqueue<T>(Future<T> Function() op) {
    final result = _lifecycleChain.then((_) => op());
    _lifecycleChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  // ── RPC / CLI delegation to the active session ─────────────────────────────

  Future<void> switchToRpcMode() {
    final session = _currentSession;
    if (session == null) {
      return Future.error(StateError('No active transport'));
    }
    return session.switchToRpcMode();
  }

  Future<void> switchToCliMode() {
    final session = _currentSession;
    if (session == null) {
      return Future.error(StateError('No device connected'));
    }
    return session.switchToCliMode();
  }

  Future<String> executeCli(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final session = _currentSession;
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
      _requireCurrentSession().writeCliText(text);

  Future<void> writeCliBytes(Uint8List bytes) =>
      _requireCurrentSession().writeCliBytes(bytes);

  Future<void> sendRpc(
    Main message, {
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    Duration sendTimeout = const Duration(seconds: 30),
  }) {
    return _requireSessionFor(priority)
        .sendRpc(message, priority: priority, sendTimeout: sendTimeout);
  }

  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) {
    return _requireSessionFor(priority).callRpcFrames(
      request,
      timeout: timeout,
      priority: priority,
      onFrame: onFrame,
      onSent: onSent,
      retainFrames: retainFrames,
      interleavable: interleavable,
      pipelined: pipelined,
    );
  }

  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) body, {
    Duration timeout = const Duration(seconds: 60),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
  }) {
    return _requireSessionFor(priority)
        .callRpcFramesMulti(body, timeout: timeout, priority: priority);
  }

  Future<FlipperRpcBatch<T>> callRpc<T extends $pb.GeneratedMessage>(
    Main request,
    T? Function(Main frame) pick, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
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
  bool isLinkDropError(Object error) {
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
  Future<bool> waitForRpcSession(Duration timeout) async {
    bool healthy() => mode == FlipperMode.rpc && (transport?.isActive ?? false);

    if (healthy()) return true;
    final restored = Completer<bool>();
    final timer = Timer(timeout, () {
      if (!restored.isCompleted) restored.complete(false);
    });
    // One subscription for both answers: every state carries the mode, and the
    // two are raised together, so a separate mode stream only meant two
    // subscriptions racing to settle the same completer.
    //
    // A terminal disconnect - no reconnect in progress - ends the wait early
    // rather than burning the whole timeout.
    final connSub = connectionStream.listen((state) {
      if (restored.isCompleted) return;
      if (state.mode == FlipperMode.rpc && healthy()) {
        restored.complete(true);
      } else if (!state.connected && !state.reconnecting) {
        restored.complete(false);
      }
    });
    if (healthy() && !restored.isCompleted) {
      restored.complete(true);
    }
    final result = await restored.future;
    timer.cancel();
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
    await connectionCtrl.close();
    await rawCtrl.close();
    await textCtrl.close();
    await messageCtrl.close();
    await broadcastCtrl.close();
    await errorCtrl.close();
    await deviceInfoCompleteCtrl.close();
    await deviceInfoWatchCtrl.close();
    await storageMutationCtrl.close();
    await _sessionsCtrl.close();
    await _heardCtrl.close();
  }
}

class FlipperCliChannel {
  FlipperCliChannel._(this._client, this._session, String backlog) {
    if (backlog.isNotEmpty) _pending.write(backlog);
    _textCtrl = StreamController<String>.broadcast(onListen: _flush);
    _tap = _session.textCtrl.stream.listen((chunk) {
      if (_textCtrl.hasListener) {
        _textCtrl.add(chunk);
      } else {
        _pending.write(chunk);
      }
    });
  }

  final FlipperClient _client;
  final FlipperSession _session;
  final StringBuffer _pending = StringBuffer();
  late final StreamController<String> _textCtrl;
  StreamSubscription<String>? _tap;
  bool _closed = false;

  FlipperDevice get device => _session.device;

  bool get isOpen =>
      !_closed && _session.isConnected && _session.mode == FlipperMode.cli;

  bool get pausesRpc => identical(_client._active, _session);

  Stream<String> get text => _textCtrl.stream;

  Stream<FlipperConnectionState> get connection =>
      _session.connectionCtrl.stream;

  Future<void> write(Uint8List bytes) => _session.writeCliBytes(bytes);

  Future<void> writeText(String text) => _session.writeCliText(text);

  Future<void> nudge() {
    final transport = _session.transport;
    if (transport == null) {
      return Future.error(StateError('No active transport'));
    }
    return transport.nudgeCli();
  }

  void _flush() {
    if (_pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    scheduleMicrotask(() {
      if (!_textCtrl.isClosed) _textCtrl.add(text);
    });
  }

  Future<void> close({bool backToRpc = true}) {
    if (_closed) return Future.value();
    _closed = true;
    unawaited(_tap?.cancel());
    _tap = null;
    unawaited(_textCtrl.close());
    return _client.serialized(() async {
      _session.cliHeld = false;
      final isActive = identical(_client._active, _session);
      if (!_session.isConnected) return;
      if (isActive) {
        if (backToRpc && _session.transport != null) {
          await _session.switchToRpcMode();
        }
      } else {
        await _session.teardownLocked('cli channel closed');
        _client._dropSessionLocked(_session);
        _client._emitSessions();
      }
    });
  }
}

// Coarse per-session connection lifecycle. `connecting` covers the whole
// connect window (transport not yet committed); `connected` mirrors
// `transport != null`. See FlipperSession._linkPhase.
