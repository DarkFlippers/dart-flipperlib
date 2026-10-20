// That an Android denial is read from the permission model, not the adapter.
//
// This file exists because the first version of `BleAccess` got Android
// exactly wrong, and `ble_access_test.dart` could not see it. That test stubs
// the plugin read and proves the *mapping*; it says nothing about whether the
// platform ever produces the state being mapped.
//
// On Android it does not. universal_ble implements the availability read as
// `bluetoothManager.adapter.state` (UniversalBlePlugin.kt) mapped through
// `Int.toAvailabilityState()` (UniversalBleHelper.kt), which covers only
// STATE_OFF / STATE_ON / STATE_TURNING_* and has no `UNAUTHORIZED` arm at
// all. A phone whose owner tapped Deny still has a powered-on adapter, so the
// base class's read answered `poweredOn` -> `granted` for a refusal.
//
// That was worse than the bug #351 set out to fix. A `denied` that reads as
// `granted` does not merely fail to raise the notice: `PermissionCenter.record`
// treats a grant as a reason to clear the user's dismissal, so the wrong
// answer actively erases state.
//
// Android signals the refusal two ways - `requestPermissions` fails with
// "Permissions denied: android.permission.BLUETOOTH_SCAN", and
// `hasPermissions` reports the still-needed set as non-empty. Only the second
// survives without asking, and the resume re-read must not ask. So the
// permission read is the authority here, and these tests pin that it is
// consulted first and that the adapter state cannot override it.
import 'package:flipperlib/src/transport/ble/android.dart';
import 'package:flipperlib/src/transport/ble/platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart' as uble;

/// The real [AndroidBlePlatform] with its two plugin calls stubbed.
///
/// Overriding only `hasScanPermission()` and `askPluginForAvailability()` is
/// the point: the ordering under test - permission first, adapter second, and the
/// adapter never consulted for a refusal - is the production body running. A
/// fake that carried its own copy of that ordering would pass on its own copy
/// being right, which is how the bug this file exists for survived its first
/// test.
class _StubbedAndroid extends AndroidBlePlatform {
  _StubbedAndroid({
    required this.permitted,
    required this.adapter,
    this.permissionReadThrows = false,
  });

  final bool permitted;
  final uble.AvailabilityState adapter;
  final bool permissionReadThrows;

  int permissionReads = 0;
  int adapterReads = 0;

  @override
  Future<bool> hasScanPermission() async {
    permissionReads++;
    if (permissionReadThrows) throw StateError('no activity');
    return permitted;
  }

  // The plugin call, not `availabilityState()`: Android does not override the
  // latter, so standing in here keeps the base's delegation under test too.
  // See the rule on `UniversalBlePlatformBase.availabilityState`.
  @override
  Future<uble.AvailabilityState> askPluginForAvailability() async {
    adapterReads++;
    return adapter;
  }

  @override
  Future<void> askPlatform() async {
    // Android delivers a refusal as a throw out of the ask. The fall-through
    // to the read is what turns it into an answer.
    if (!permitted) throw StateError('Permissions denied: BLUETOOTH_SCAN');
  }
}

void main() {
  test('a refused permission on a powered-on adapter reads denied', () async {
    // The regression. The adapter is on, which is what the base class used to
    // read, and the answer must still be `denied`.
    final platform = _StubbedAndroid(
      permitted: false,
      adapter: uble.AvailabilityState.poweredOn,
    );

    expect(await platform.readAccess(), BleAccess.denied);
    expect(
      platform.adapterReads,
      0,
      reason: 'the adapter cannot overrule a refused permission',
    );
  });

  test('a granted permission still defers to the adapter', () async {
    // So a user with Bluetooth switched off gets the sentence that belongs to
    // that, not a permission notice they can do nothing with.
    final platform = _StubbedAndroid(
      permitted: true,
      adapter: uble.AvailabilityState.poweredOff,
    );

    expect(await platform.readAccess(), BleAccess.off);
    expect(platform.adapterReads, 1);
  });

  test('granted and powered on is granted', () async {
    final platform = _StubbedAndroid(
      permitted: true,
      adapter: uble.AvailabilityState.poweredOn,
    );

    expect(await platform.readAccess(), BleAccess.granted);
  });

  test('a permission read that throws is unknown, not denied', () async {
    // `hasPermissions` throws when a required permission is missing from the
    // manifest - a packaging mistake - and where there is no activity to
    // answer from. Neither is a user decision.
    final platform = _StubbedAndroid(
      permitted: false,
      adapter: uble.AvailabilityState.poweredOn,
      permissionReadThrows: true,
    );

    expect(await platform.readAccess(), BleAccess.unknown);
  });

  test('an ask that throws reports the refusal the read finds', () async {
    // The two halves together, and the case that was broken end to end: on
    // Android a refusal arrives as a throw out of the ask, and the
    // fall-through to the read is what turns it into an answer. With the base
    // class's read that produced `granted`; with the permission read it
    // produces `denied`.
    final platform = _StubbedAndroid(
      permitted: false,
      adapter: uble.AvailabilityState.poweredOn,
    );

    expect(await platform.requestPermissions(), BleAccess.denied);
    expect(platform.permissionReads, 1);
  });
}
