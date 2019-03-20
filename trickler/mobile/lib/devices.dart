import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'model.dart';
import 'actions.dart';
import 'globals.dart' as globals;
import 'header.dart';

class DevicesPage extends StatefulWidget {
  DevicesPage({ Key key }) : super(key: key);

  final String title = 'Bluetooth Devices';

  @override
  _DevicesPageState createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  String _btDeviceName = 'Trickler';

  FlutterBlue _flutterBlue = FlutterBlue.instance;

  dynamic _scanSubscription;
  Map<DeviceIdentifier, ScanResult> _scanResults = Map();

  dynamic _deviceConnection;

  List<int> _stability = [];
  List<int> _weight = [];
  List<int> _unit = [];

  void _scanDevices(Function dispatch) {
    try {
      bool foundPeripheral = false;
      dispatch(SetConnectionStatus(globals.connecting));
      // Listen for BT Devices for 5 seconds
      _scanSubscription = _flutterBlue.scan(timeout: const Duration(seconds: 5)).listen((scanResult) {
        // Save all results to local state
        setState(() {
          _scanResults[scanResult.device.id] = scanResult;
        });
        if (scanResult.advertisementData.localName == _btDeviceName && !foundPeripheral) {
          // Connect before 5 second timeout
          foundPeripheral = true;
          _connectToDevice(scanResult.device, dispatch);
        }
      }, onDone: () => _stopScan(dispatch, foundPeripheral));
    } catch (e) {
      print(e.toString());
    }
  }

  void _stopScan(Function dispatch, bool foundPeripheral) {
    // Stop scanning...
    _scanSubscription?.cancel();
    _scanSubscription = null;
    bool foundDevice = foundPeripheral;
    if (!foundDevice) {
      // 
      // If we didn't connect before 5 second timeout:
      // loop through results and double check.
      // 
      // TODO: Turn all results into selectable devices
      // to allow for connection to non-trickler devices
      // 
      _scanResults.forEach((key, value) {
        if (value.advertisementData.localName == _btDeviceName) {
          foundDevice = true;
          _connectToDevice(value.device, dispatch);
        }
      });
      dispatch(SetConnectionStatus(globals.disconnected));
    }
  }

  void _connectToDevice(BluetoothDevice device, Function dispatch) async {
    // Stop the scan before 5 second timeout
    _stopScan(dispatch, true);
    _deviceConnection = _flutterBlue
      .connect(device, timeout: Duration(seconds: 4))
      .listen((s) {
        // Connect to device and listen for data
        if (s == BluetoothDeviceState.connected) {
          print('\n\n\nConnected!\n\n\n\n');
          dispatch(SetConnectionStatus(globals.connected));
          dispatch(SetDevice(device));
          _getServices(device, dispatch);
        } else if (s == BluetoothDeviceState.disconnected) {
          _disconnect(dispatch);
        }
      }, onDone: () => _disconnect(dispatch));
  }

  void _disconnect(Function dispatch) {
    _deviceConnection?.cancel();
    print('\n\n\nDisconnecting...\n\n\n\n');
    dispatch(SetConnectionStatus(globals.disconnected));
    dispatch(SetDevice(BluetoothDevice(id:DeviceIdentifier('000'))));
    setState(() {
      _stability = [];
      _weight = [];
      _unit = [];
    });
  }

  void _getServices(BluetoothDevice device, Function dispatch) {
    // Discover all advertised trickler services
    device.discoverServices().then((services) {
      print('\n\n\nGOT ${services.length} SERVICES...\n\n\n');
      List<BluetoothCharacteristic> chars = [];
      services.forEach((service) {
        // Find the service we need for data readout
        if (service.uuid.toString() == globals.tricklerServiceId) {
          dispatch(SetService(service));
          print('\n\n\nCHRACTERISTICS: ${service.characteristics.length}\n\n\n');
          service.characteristics.forEach((char) {
            chars.add(char);
          });
        }
      });
      // Read all provided characteristics
      _readCharacteristics(device, chars, 0);
    });
  }

  dynamic _readCharacteristics(BluetoothDevice device, List<BluetoothCharacteristic> chars, int i) {
    // Rucursively read characteristics one at a time
    List<String> charNames = ['STABLITY', 'WEIGHT', 'UNIT'];

    BluetoothCharacteristic char = chars[i];
    if (char.properties.read) {
      print('\n\n\nREADING ${charNames[i]}...\n\n\n');
      device.readCharacteristic(char).then((readChar) {
        print('\n\n${charNames[i]} PROPERTIES');
        print('NOTIFY: ${char.properties.notify}');
        print('READ: ${char.properties.read}');
        print('WRITE: ${char.properties.write}\n\n');
        print('${charNames[i]}: ${char.value}\n\n');
        // 
        // Update local state to reflect characteristics
        // TODO: Migrate to global state for data persistence
        // 
        setState(() {
          if (i == 0) {
            _stability = readChar;
          } else if (i == 1) {
            _weight = readChar;
          } else if (i == 2) {
            _unit = readChar;
          }
        });
        if (i + 1 >= chars.length) {
          return [readChar];
        }
        return List.from([readChar])..addAll(_readCharacteristics(device, chars, i + 1));
      });
    } else {
      print('\n\n\nCAN\'T READ ${charNames[i]}');
      print('\n\n${charNames[i]} PROPERTIES');
      print('NOTIFY: ${char.properties.notify}');
      print('READ: ${char.properties.read}');
      print('WRITE: ${char.properties.write}\n\n');
    }
  }

  Widget _getDeviceInfo(BuildContext context, BluetoothDevice device) {
    if (device.id != DeviceIdentifier('000')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(bottom: 20.0),
            child: Text("Connected to: ${device.name}",
              style: TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding:EdgeInsets.only(bottom: 8.0),
            child: Text("Stability: ${_stability.length > 0 ? globals.stabilityList[_stability[0]] : ''}",
              style: TextStyle(
                fontSize: 18.0,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Padding(
            padding:EdgeInsets.only(bottom: 8.0),
            child: Text("Weight: ${_weight.toString()}",
              style: TextStyle(
                fontSize: 18.0,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Padding(
            padding:EdgeInsets.only(bottom: 8.0),
            child: Text("Unit: ${_unit.length > 0 ? globals.unitsList[_unit[0]] : ''}",
              style: TextStyle(
                fontSize: 18.0,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      );
    }
    return Text('You are not connected to a device!',
      style: TextStyle(
        fontSize: 18.0,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.0),
          child: Header(
          key: Key('Header'),
          title: widget.title,
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            StoreConnector<AppState, BluetoothDevice>(
              converter: (store) => store.state.device,
              builder: _getDeviceInfo,
            ),
          ],
        ),
      ),
      floatingActionButton: StoreConnector<AppState, Function>(
        converter: (store) {
          return (action) => store.dispatch(action);
        },
        builder: (context, dispatch) {
          return StoreConnector<AppState, BluetoothDevice>(
            converter: (store) => store.state.device,
            builder: (context, device) {
              if (device.id != DeviceIdentifier('000')) {
                return FloatingActionButton(
                  heroTag: 'Dissconnect',
                  onPressed: () => _disconnect(dispatch),
                  tooltip: 'Dissconnect',
                  backgroundColor: Colors.red,
                  child: Icon(Icons.bluetooth_disabled),
                );
              }
              return FloatingActionButton(
                heroTag: 'ScanBTDevices',
                onPressed: () => _scanDevices(dispatch),
                tooltip: 'Scan for Devices',
                backgroundColor: Colors.green,
                child: Icon(Icons.bluetooth_searching),
              );
            },
          );
        },
      ),
    );
  }
}