import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';

class BluetoothController {
  // Ya no se utiliza FlutterBluePlus.instance
  final ValueNotifier<List<ScanResult>> devices = ValueNotifier([]);
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeCharacteristic;

  /// Escanear dispositivos BLE y notificar cambios
  Future<void> scanForDevices() async {
    devices.value = []; // Limpiar lista anterior

    // Iniciar escaneo (método estático)
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    // Escuchar resultados del escaneo
    FlutterBluePlus.scanResults.listen((results) {
      devices.value = results;
    });

    // Detener escaneo
    await FlutterBluePlus.stopScan();
  }

  /// Conectar a un dispositivo específico por nombre
  Future<void> connectToDeviceByName(String deviceName) async {
    // Asegurar que el escaneo esté detenido
    await FlutterBluePlus.stopScan();

    // Buscar el dispositivo por nombre en los resultados detectados
    final result = devices.value.firstWhere(
      (result) => result.device.platformName == deviceName,
      orElse: () => throw Exception("Dispositivo no encontrado"),
    );

    connectedDevice = result.device;

    // Intentar la conexión
    await connectedDevice!.connect(license: License.free, autoConnect: false);
    debugPrint("Conectado a: $deviceName");

    // Descubrir servicios y características
    List<BluetoothService> services = await connectedDevice!.discoverServices();

    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.write) {
          writeCharacteristic = characteristic;
          debugPrint("Característica de escritura encontrada.");
          return;
        }
      }
    }

    throw Exception(
        "No se encontró una característica de escritura en el dispositivo.");
  }

  /// Enviar un comando al dispositivo conectado
  Future<void> sendCommand(String command) async {
    if (writeCharacteristic != null && connectedDevice != null) {
      await writeCharacteristic!.write(command.codeUnits);
      debugPrint("Comando enviado: $command");
    } else {
      throw Exception(
          "No hay dispositivo conectado o característica de escritura no encontrada.");
    }
  }

  /// Desconectar del dispositivo actual
  Future<void> disconnect() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      debugPrint("Desconectado de: ${connectedDevice!.platformName}");
      connectedDevice = null;
      writeCharacteristic = null;
    } else {
      debugPrint("No hay dispositivo conectado.");
    }
  }

  /// Liberar recursos
  void dispose() {
    devices.dispose();
  }
}
