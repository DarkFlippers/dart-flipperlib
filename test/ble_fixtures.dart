// The shape of a Flipper's BLE service, shared by the tests that drop one
// characteristic from it.
//
// Pulled out when the third file carried it, which is the threshold the parent
// repo's `archive_fakes.dart` records for itself. The line count is not the
// reason: [allFlipperChars] is the *premise* of its callers - every case in
// `ble_services_missing_test.dart` and the second group of
// `ble_overflow_single_read_test.dart` is "the full set minus exactly one" -
// and two copies of a premise is one that can drift. Add a fifth
// characteristic to the link, update one copy, and the other keeps compiling
// and passing while silently testing a different shape: a case that reads as
// "missing one" would be missing two. A `BleChar` signature change or a UUID
// rename is caught by the compiler; that is not.
//
// What is deliberately **not** here: the `BleOps` fakes. The three that exist
// answer genuinely different method sets - two plugin calls for
// `ble_mtu_settle_test.dart`, two plus `noSuchMethod` for
// `ble_services_missing_test.dart`, the whole encrypted setup with a read
// counter for `ble_overflow_single_read_test.dart` - and `noSuchMethod` has to
// be declared on the class that leaves members unimplemented, so a mixin
// cannot supply it. One fake configurable for three unrelated paths would be
// worse than three honest ones.
//
// `ble_mtu_settle_test.dart`'s own `_char(uuid, {write, notify})` also stays
// where it is: its per-flag precision is the subject under test there, and
// folding it into the all-true shape below would weaken the one file where the
// flags matter.
import 'package:flipperlib/src/model/discovered.dart';
import 'package:flipperlib/src/transport/ble/gatt.dart';
import 'package:flipperlib/src/transport/ble/link.dart';
import 'package:universal_ble/universal_ble.dart' as uble;

/// A characteristic with every flag a Flipper's set, for the cases that care
/// which characteristics exist rather than what they permit.
BleChar flipperChar(String uuid) => BleChar(
  uuid,
  canWrite: true,
  canWriteNoRsp: true,
  canNotify: true,
  canIndicate: false,
);

/// Every characteristic a Flipper carries, so a case can drop exactly one.
List<BleChar> allFlipperChars() => [
  flipperChar(flipperBleTxUuid),
  flipperChar(flipperBleRxUuid),
  flipperChar(UniversalBleTransportBase.overflowCharUuid),
  flipperChar(UniversalBleTransportBase.rpcStatusCharUuid),
];

/// The device every one of these tests connects to.
BleDiscoveredDevice testFlipperDevice() =>
    BleDiscoveredDevice(uble.BleDevice(deviceId: 'dev', name: 'Flipper'));

/// A concrete [UniversalBleTransportBase], which is abstract only because
/// `openTransport` is per platform.
class TestBleTransport extends UniversalBleTransportBase {
  TestBleTransport(super.device, super.ops);
}
