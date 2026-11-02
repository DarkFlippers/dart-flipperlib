/// [id] in the one form every comparison and map key in this library expects.
///
/// From universal_ble 3.0.0 a device id is emitted in lower-case on every
/// native platform; through 2.x each platform reported its native case, and
/// Android upper-cased MACs. Any case is still accepted as *input* - the
/// plugin converts to the form its native side needs at its own boundary,
/// because Android's `getRemoteDevice` wants upper-case - so an id in the
/// wrong case connects and then matches nothing. That is the failure worth
/// naming: no connected state, no notifications, and the same Flipper listed
/// twice. #444.
///
/// Written here rather than delegated to `UniversalBle.canonicalDeviceId`,
/// which exists for exactly this and gives the same answer on every platform
/// this library implements. The delegation costs a first touch of the plugin:
/// reading `UniversalBle._platform` constructs the backend for the host, which
/// sets up a Pigeon callback channel, and on Linux builds a `BlueZClient`
/// whose own constructor calls `DBusClient.system()` - parsing
/// `DBUS_SYSTEM_BUS_ADDRESS` eagerly and throwing `FormatException`,
/// synchronously, on a host whose address carries no transport prefix. This
/// function runs at the top of `connectBleAddress`, above the availability
/// gate, so delegating would put that throw on the one path #443 exists to
/// keep clear. Lower-casing a string is not worth a D-Bus client.
///
/// The premise is that every platform this library has is one where a device
/// id is a Bluetooth address - a MAC on Android, Linux and Windows, an opaque
/// per-app peer UUID on Apple - and that addresses are case-insensitive. Web
/// is the exception the plugin carries and this does not: there an id is an
/// opaque, case-sensitive browser token that has to stay verbatim. If a web
/// platform is ever added here, this is the one function that has to learn
/// about it.
///
/// `test/ble_device_id_test.dart` holds the line from the other side: it
/// initialises no binding, so a body that went back to asking the plugin
/// fails there rather than on a user's machine.
String canonicalBleDeviceId(String id) => id.toLowerCase();
