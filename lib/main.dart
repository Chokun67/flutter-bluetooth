import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter BLE Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const BluetoothScanPage(),
    );
  }
}

class BluetoothScanPage extends StatefulWidget {
  const BluetoothScanPage({super.key});

  @override
  _BluetoothScanPageState createState() => _BluetoothScanPageState();
}

class _BluetoothScanPageState extends State<BluetoothScanPage> {
  List<BluetoothDevice> devicesList = [];
  BluetoothDevice? connectedDevice;
  List<BluetoothService> services = [];
  StreamSubscription<List<int>>? valueSubscription;
  String receivedData = "";
  bool isScanning = false;
  StreamSubscription<BluetoothAdapterState>? _stateSubscription;
  BluetoothAdapterState bluetoothState = BluetoothAdapterState.unknown;

  @override
  void initState() {
    super.initState();
    checkBluetoothSupport();
    ensureBluetoothIsOn();
    checkPermissions();
    listenBluetoothState();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    valueSubscription?.cancel();
    super.dispose();
  }

  Future<void> checkBluetoothSupport() async {
    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth not supported by this device");
      showBluetoothNotSupportedDialog();
      return;
    }
  }

  Future<void> showBluetoothNotSupportedDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth Not Supported'),
        content: const Text('This device does not support Bluetooth.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> ensureBluetoothIsOn() async {
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
  }

  Future<void> checkPermissions() async {
    final status = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse
    ].request();

    if (status[Permission.bluetoothScan] != PermissionStatus.granted ||
        status[Permission.bluetoothConnect] != PermissionStatus.granted ||
        status[Permission.locationWhenInUse] != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissions not granted.')),
      );
    }
  }

  void listenBluetoothState() {
    _stateSubscription = FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        bluetoothState = state;
      });
      print('Bluetooth State: $state');
    });
  }

  Future<void> startScan() async {
    if (bluetoothState != BluetoothAdapterState.on) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable Bluetooth to scan for devices.'),
        ),
      );
      return;
    }

    setState(() {
      isScanning = true;
      devicesList.clear();
    });

    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      setState(() {
        for (ScanResult result in results) {
          if (!devicesList.any((d) => d.remoteId == result.device.remoteId)) {
            devicesList.add(result.device);
          }
        }
      });
    }, onError: (e) {
      print('Scan error: $e');
    });

    await FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency,
      timeout: const Duration(seconds: 10),
    );

    await FlutterBluePlus.isScanning.where((val) => val == false).first;
    subscription.cancel();

    setState(() {
      isScanning = false;
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    setState(() {
      connectedDevice = device;
    });

    await device.connect();
    print('Connected to ${device.platformName}');
    discoverServices(device);
  }

  Future<void> discoverServices(BluetoothDevice device) async {
    services = await device.discoverServices();
    for (BluetoothService service in services) {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.properties.notify) {
          await characteristic.setNotifyValue(true);
          valueSubscription =
              characteristic.onValueReceived.listen((value) {
            setState(() {
              receivedData = value.toString();
            });
            print('Data received: $receivedData');
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner'),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: isScanning ? null : startScan,
            child: Text(isScanning ? 'Scanning...' : 'Start Scan'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: devicesList.length,
              itemBuilder: (context, index) {
                BluetoothDevice device = devicesList[index];
                return ListTile(
                  title: Text(device.platformName.isNotEmpty
                      ? device.platformName
                      : "Unknown Device"),
                  subtitle: Text(device.remoteId.toString()),
                  trailing: ElevatedButton(
                    onPressed: () {
                      connectToDevice(device);
                    },
                    child: const Text('Connect'),
                  ),
                );
              },
            ),
          ),
          if (connectedDevice != null)
            Text('Connected to ${connectedDevice!.platformName}'),
          if (receivedData.isNotEmpty)
            Text('Received Data: $receivedData'),
        ],
      ),
    );
  }
}
