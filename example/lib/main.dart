import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: DevicesPage(), title: 'flipperlib example');
}

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final FlipperClient _flipper = FlipperClient();

  List<FlipperDevice> _devices = const [];
  FlipperDevice? _connected;
  List<String> _rootEntries = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _flipper.devicesStream.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
    _scan();
  }

  @override
  void dispose() {
    _flipper.disconnect();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    await _flipper.initialize();
    final devices = await _flipper.refreshDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _busy = false;
    });
  }

  Future<void> _connect(FlipperDevice device) async {
    setState(() => _busy = true);
    final connected = await _flipper.connect(device);
    final listing = await _flipper.storageList(ListRequest(path: '/ext'));
    if (!mounted) return;
    setState(() {
      _connected = connected;
      _rootEntries = [
        for (final response in listing.items)
          for (final entry in response.file) entry.name,
      ];
      _busy = false;
    });
  }

  Future<void> _disconnect() async {
    await _flipper.disconnect();
    if (!mounted) return;
    setState(() {
      _connected = null;
      _rootEntries = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connected;
    return Scaffold(
      appBar: AppBar(
        title: Text(connected?.name ?? 'Flipper devices'),
        actions: [
          IconButton(
            onPressed: _busy ? null : (connected == null ? _scan : _disconnect),
            icon: Icon(connected == null ? Icons.refresh : Icons.link_off),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : connected == null
          ? ListView(
              children: [
                for (final device in _devices)
                  ListTile(
                    leading: Icon(device.isUsb ? Icons.usb : Icons.bluetooth),
                    title: Text(device.name),
                    subtitle: Text(device.id),
                    onTap: () => _connect(device),
                  ),
              ],
            )
          : ListView(
              children: [
                for (final name in _rootEntries)
                  ListTile(title: Text('/ext/$name')),
              ],
            ),
    );
  }
}
