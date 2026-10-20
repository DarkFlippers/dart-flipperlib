// That a libusb symbol newer than the oldest libusb we load is not bound in
// the constructor.
//
// This exists because the behavioural test for QUNLEASHED-11 cannot run here.
// `libusb_optional_symbols_test.dart` checks the contract - ask, and get an
// answer - but the case that crashed needs a libusb older than the symbol, and
// the host running this suite is whatever it is: CI's is newer, and on Windows
// the probe finds no library and answers null before reaching the constructor.
// The real check was a run under WSL on Ubuntu 20.04 (libusb 1.0.23), and a run
// is not a guard. The next person to add a symbol here gets no signal from the
// suite at all.
//
// So this one reads the source, the way this project does when the condition is
// a property of the machine (ADR 0004). It would rather not: the rule belongs
// in the API, as a `_required` / `_optional` pair that a caller cannot omit.
// That does not compile - `lookupFunction` needs a statically concrete native
// type, so a type parameter in that position is
// `must_be_a_native_function_type` - which is why the production code carries
// the rule in prose and this file carries the enforcement. If flipperlib ever
// takes an `analyzer` dev dependency, this is one of the two tests to rewrite
// against a parser, as ADR 0004 asks.
//
// `_withoutComments` from `plugin_reach_guard_test.dart` is deliberately not
// used: the occurrence counts here are over the whole file, comments included,
// because the doc comments name the symbol unquoted and these assertions count
// the quoted form. That file has the opposite requirement and says so.
import 'dart:io';

import 'package:flipperlib/src/dfu/libusb/libusb.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = 'lib/src/dfu/libusb/libusb.dart';

/// Symbols that do not exist in [Libusb.floorVersion].
///
/// `libusb_wrap_sys_device` is deliberately **not** here: it is Android-only in
/// practice, like `libusb_init_context`, but it landed in 1.0.23 and so is in
/// the floor. That difference is the whole rule, and the reason this is a list
/// rather than one constant.
const _symbolsAboveTheFloor = <String>[
  'libusb_init_context', // 1.0.27 - QUNLEASHED-11
];

/// The text between `Libusb._`'s opening brace and its match.
///
/// Brace-matched rather than sliced at an indentation level, because the braces
/// are the structure and the indentation is `dart format`'s opinion. A reflow
/// should not be able to fail this file, and an earlier draft that keyed on a
/// two-space `'  }'` could.
String _constructorBody(String source) {
  final signature = source.indexOf('Libusb._(this._lib) {');
  expect(signature, isNot(-1), reason: 'the constructor was renamed');

  var i = source.indexOf('{', signature);
  var depth = 0;
  final open = i;
  for (; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  fail('the constructor has no matching closing brace');
}

void main() {
  late String source;

  setUpAll(() {
    final file = File(_source);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$_source moved; this test cannot see what it is guarding',
    );
    source = file.readAsStringSync();
  });

  test(
    'the floor is declared, so the rule has something to measure against',
    () {
      // Named rather than implied: the list above only means anything relative
      // to a version somebody wrote down.
      expect(Libusb.floorVersion, '1.0.23');
    },
  );

  group('the constructor binds only symbols the floor has', () {
    test('no symbol above the floor is looked up in it', () {
      final body = _constructorBody(source);

      for (final symbol in _symbolsAboveTheFloor) {
        expect(
          body,
          isNot(contains(symbol)),
          reason:
              "'$symbol' is newer than Libusb.floorVersion, so binding it in "
              'the constructor makes it required on every platform. That is '
              'QUNLEASHED-11: the app rendered an error widget instead of '
              'itself on every launch on Ubuntu 20.04 and 22.04. Look it up '
              'in a `_lookupX` helper that answers null instead.',
        );
      }
    });

    test('and binds the ones it does have', () {
      final body = _constructorBody(source);

      // The complement, so the case above cannot pass by the constructor
      // having stopped binding anything - which is also a regression, just a
      // slower one: a symbol resolved on first use fails from whichever
      // transfer reaches it rather than once, at load.
      expect(body, contains("'libusb_init'"));
      expect(body, contains("'libusb_get_device_list'"));
      expect(body, contains("'libusb_control_transfer'"));
      // Android-only in practice and eager anyway, because 1.0.23 has it.
      // This is the case that pins the rule as "older than the floor" rather
      // than "used on every platform".
      expect(body, contains("'libusb_wrap_sys_device'"));
    });
  });

  group('a symbol outside the constructor', () {
    test('is looked up in exactly one place', () {
      // The quoted form, which is a lookup and not prose: the doc comments
      // name the symbol without quoting it, so they do not count here.
      for (final symbol in [
        ..._symbolsAboveTheFloor,
        'libusb_set_auto_detach_kernel_driver',
      ]) {
        expect(
          "'$symbol'".allMatches(source).length,
          1,
          reason: "a second mention of '$symbol' is another binding site",
        );
      }
    });

    test('has a nullable field, so absence is a value', () {
      // ADR 0009, and the difference between this and the first version of
      // the fix, which made `initContext` a lazy throw: a `late final` whose
      // initializer throws stays unassigned and re-runs on every read instead
      // of latching, so the failure repeats for the life of the object.
      // Measured, not assumed.
      expect(source, contains('LibusbInitContext? initContext'));
      // Not above the floor - 1.0.16 - but optional at its call site, which
      // `usb_device.dart` expressed with a `try` and the type now says.
      expect(
        source,
        contains('LibusbSetAutoDetach? setAutoDetachKernelDriver'),
      );
    });

    test('and its lookup cannot throw', () {
      // Matched loosely on whitespace so a reflow is not a failure; what has
      // to hold is that each helper wraps the lookup and answers null.
      expect(
        RegExp(r'on ArgumentError \{\s*return null;').allMatches(source).length,
        2,
        reason: 'expected one guarded lookup per optional symbol',
      );
    });
  });

  test('the load probe stays a probe', () {
    // `libusb_init` has been there since 1.0.0, which is what makes it a "this
    // is libusb" check and not a version check. Probing anything newer would
    // silently reject a working older library - the same mistake as binding
    // one, one layer earlier.
    final probe = source.indexOf('lib.lookup<NativeFunction<_InitNative>>');
    expect(probe, isNot(-1), reason: 'the candidate probe was reshaped');
    expect(source.substring(probe, probe + 60), contains("'libusb_init'"));
  });
}
