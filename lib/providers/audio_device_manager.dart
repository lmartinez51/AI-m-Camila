import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class AudioDeviceManager extends ChangeNotifier {
  bool _areHeadphonesConnected = false;

  bool get areHeadphonesConnected => _areHeadphonesConnected;

  AudioDeviceManager() {
    initialize();
  }

  /// Initializes the audio session and sets up event listeners.
  Future<void> initialize() async {
    try {
      final session = await AudioSession.instance;
      // Removed manual configuration to restore legacy behavior.

      await session.setActive(true);

      // Listen for changes in audio devices
      session.devicesChangedEventStream.listen((_) async {
        await _updateHeadphoneStatus(session);
      });

      // Initialize the current state
      await _updateHeadphoneStatus(session);
    } catch (e) {
      debugPrint('Error initializing AudioDeviceManager: $e');
    }
  }

  /// Updates the status of connected headphones.
  Future<void> _updateHeadphoneStatus(AudioSession session) async {
    try {
      final devices = await session.getDevices();
      final bool newStatus = devices.any((device) =>
          device.type == AudioDeviceType.wiredHeadset ||
          device.type == AudioDeviceType.wiredHeadphones ||
          device.type == AudioDeviceType.bluetoothA2dp ||
          device.type == AudioDeviceType.bluetoothLe ||
          device.type.toString().toLowerCase().contains('usb') ||
          device.type.toString().toLowerCase().contains('headset'));

      // Print detected device types
      for (var device in devices) {
        debugPrint('Detected device type: ${device.type}');
      }
      if (_areHeadphonesConnected != newStatus) {
        _areHeadphonesConnected = newStatus;
        debugPrint(
            'Are Headphones Connected updated: $_areHeadphonesConnected');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating headphone status: $e');
    }
  }

  /// Manually checks the current headphone connection status.
  Future<void> checkHeadphoneStatus() async {
    try {
      final session = await AudioSession.instance;
      await _updateHeadphoneStatus(session);
    } catch (e) {
      debugPrint('Error checking headphone status: $e');
    }
  }

  /// Habilita o deshabilita el speakerphone del dispositivo y ajusta el volumen
  Future<void> toggleSpeaker(bool enable) async {
    try {
      if (enable) {
        await Helper.setSpeakerphoneOn(true); // Habilitar el speakerphone
      } else {
        await Helper.setSpeakerphoneOn(false); // Deshabilitar el speakerphone
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error toggling speaker: $e');
    }
  }

  @override
  void dispose() {
    // Clean up resources if needed
    super.dispose();
  }
}
