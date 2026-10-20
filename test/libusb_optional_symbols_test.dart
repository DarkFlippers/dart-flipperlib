// That loading libusb answers instead of throwing.
//
// `Libusb.instance` is documented to return null "when the platform has no
// libusb build (so callers can degrade gracefully instead of crashing)", and
// until QUNLEASHED-11 that was not true of a libusb that loaded and then
// turned out to be older than one of the symbols the constructor bound.
// `libusb_init_context` arrived in libusb 1.0.27; a distro ships whatever it
// froze - 1.0.23 on Ubuntu 20.04, 1.0.25 on 22.04 - and the lookup threw out
// of the constructor on both.
//
// Where it landed is why it took the app rather than a feature. There are six
// call sites, but the *first* one at launch is `DfuDetector.available` by way
// of `LibusbHostBackend.available`, reached from `DeviceController`'s field
// initialiser inside `_QUnleashedAppState.build` - so the throw was reported
// through `FlutterError.onError` from `build`, and the framework rendered an
// error widget in place of the app. On every launch, re-thrown on every
// rebuild, on a machine whose only sin was being an LTS.
//
// What this file can check anywhere is the contract: ask, and get an answer.
// What it cannot check is the case that produced the crash, because that needs
// a libusb older than the symbol and the host running the suite is whatever it
// is - `flutter analyze`'s runner and CI are both newer, and on Windows the
// probe finds no library at all and answers null before reaching the
// constructor. The real verification was a run under WSL on Ubuntu 20.04,
// whose libusb is 1.0.23 and has no `libusb_init_context`: reverted, the probe
// below throws `ArgumentError: Failed to lookup symbol`; as it stands, it
// loads and enumerates the bus.
//
// A run is not a guard, so the decision itself is pinned by
// `libusb_symbol_binding_test.dart`, which reads the source and fails on any
// host the moment the binding moves back into the constructor. These cases
// cover what the contract looks like from outside; that one covers the thing
// that broke it.
import 'package:flipperlib/src/dfu/libusb/libusb.dart';
import 'package:flipperlib/src/dfu/libusb_host_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Libusb.instance', () {
    test('answers rather than throwing', () {
      // The whole of the regression, in the only terms every host shares. A
      // null here is a real answer and the one every caller already handles.
      expect(() => Libusb.instance, returnsNormally);
    });

    test('is memoised, so neither outcome is re-derived', () {
      // Named for what it checks on most hosts. Where libusb loads this pins
      // `_instance`; where it does not, `identical(null, null)` holds
      // trivially and the case says nothing - the latch that matters there is
      // `_unavailable`, and only a host older than the symbol can show it.
      // `libusb_symbol_binding_test.dart` covers that side by reading the
      // source instead.
      expect(Libusb.instance, same(Libusb.instance));
    });

    test('is usable when it is not null', () {
      final usb = Libusb.instance;
      if (usb == null) {
        // Not a skip: "no libusb on this host" is the other half of the
        // contract and it has just been asserted. There is nothing further to
        // ask of it.
        return;
      }

      // The symbols the constructor binds eagerly are the ones the
      // enumeration and transfer paths need, so a non-null answer has to be a
      // working one - otherwise
      // the guard added in `instance` would be hiding the crash rather than
      // answering it. Asserted through the backend that production asks,
      // because what has to hold is that *that* works.
      expect(
        LibusbSession.context,
        isNotNull,
        reason: 'libusb loaded but could not create a context',
      );

      final backend = LibusbHostBackend();
      expect(backend.available, isTrue);
      // Enumerates the real bus. No assertion on the answer - whether a
      // Flipper is sitting in DFU on the machine running this is not this
      // suite's business - only that asking works.
      expect(backend.isPresentSync, returnsNormally);
    });
  });
}
