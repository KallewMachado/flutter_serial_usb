import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _checkPermissions();
  runApp(MyApp());
}

Future<void> _checkPermissions() async {
  if (await Permission.nearbyWifiDevices.isDenied ||
      await Permission.nearbyWifiDevices.isPermanentlyDenied) {
    await Permission.nearbyWifiDevices.request();
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  UsbPort? _port;
  String _status = "Idle";
  List<Widget> _ports = [];
  List<String> _serialData = [];
  ScrollController _scrollController = ScrollController();

  StreamSubscription<String>? _subscription;
  Transaction<String>? _transaction;
  UsbDevice? _device;

  TextEditingController _textController = TextEditingController();

  Future<bool> _connectTo(device) async {
    _serialData.clear();

    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_port != null) {
      _port!.close();
      _port = null;
    }

    if (device == null) {
      _device = null;
      setState(() {
        _status = "Disconnected";
      });
      return true;
    }

    _port = await device.create();
    if (await (_port!.open()) != true) {
      setState(() {
        _status = "Failed to open port";
      });
      return false;
    }
    _device = device;

    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(
      115200,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    _transaction = Transaction.stringTerminated(
      _port!.inputStream as Stream<Uint8List>,
      Uint8List.fromList([13, 10]),
    );

    _subscription = _transaction!.stream.listen((String line) {
      setState(() {
        _serialData.add(line);
        if (_serialData.length > 100) {
          _serialData.removeAt(0);
        }
      });
      _scrollToBottom();
    });

    setState(() {
      _status = "Connected";
    });
    return true;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _getPorts() async {
    _ports = [];
    List<UsbDevice> devices = await UsbSerial.listDevices();
    if (!devices.contains(_device)) {
      _connectTo(null);
    }

    devices.forEach((device) {
      _ports.add(
        ListTile(
          leading: Icon(Icons.usb),
          title: Text(device.productName ?? "Unknown Device"),
          subtitle: Text(device.manufacturerName ?? "Unknown Manufacturer"),
          trailing: ElevatedButton(
            child: Text(_device == device ? "Disconnect" : "Connect"),
            onPressed: () {
              _connectTo(_device == device ? null : device).then((res) {
                _getPorts();
              });
            },
          ),
        ),
      );
    });

    setState(() {});
  }

  @override
  void initState() {
    super.initState();

    _requestPermissionAndLoad();

    UsbSerial.usbEventStream!.listen((UsbEvent event) {
      _getPorts();
    });
  }

  Future<void> _requestPermissionAndLoad() async {
    if (await Permission.nearbyWifiDevices.request().isGranted) {
      _getPorts();
    } else {
      setState(() {
        _status = "USB permission denied";
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
    _connectTo(null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: _getPorts,
          child: Icon(Icons.refresh),
        ),
        appBar: AppBar(title: const Text('USB Serial Plugin example app')),
        body: Column(
          children: <Widget>[
            Text(
              _ports.isNotEmpty
                  ? "Available Serial Ports"
                  : "No serial devices available",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ..._ports,
            Text('Status: $_status\n'),
            Text('info: ${_port.toString()}\n'),
            ListTile(
              title: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Text To Send',
                ),
              ),
              trailing: ElevatedButton(
                onPressed:
                    _port == null
                        ? null
                        : () async {
                          if (_port == null) {
                            return;
                          }
                          String data = "${_textController.text}\r\n";
                          await _port!.write(
                            Uint8List.fromList(data.codeUnits),
                          );
                          _textController.text = "";
                        },
                child: Text("Send"),
              ),
            ),
            Expanded(
              child: Container(
                padding: EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _serialData.length,
                  itemBuilder: (context, index) {
                    return Text(_serialData[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
