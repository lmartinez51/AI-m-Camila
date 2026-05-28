// @file websocket_service.dart
// @brief Signaling service handler for internal WebSocket transmission layer.
// @author Lorenzo Martínez
// @date 2026-03-30
// @version 1.0.0

import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter/foundation.dart';

/// @brief Standalone service encapsulating low-level WebSocket connection management.
class SignalingService {
  final String signalingServerUrl;
  WebSocketChannel? _channel;
  Function(Map<String, dynamic>)? onMessageReceived;
  Function? onConnectionClosed;
  Function? onConnectionError;

  SignalingService(this.signalingServerUrl);

  /// @brief Initializes the WebSocket channel and sets up fundamental stream listeners.
  void connect() {
    _channel = WebSocketChannel.connect(
      Uri.parse(signalingServerUrl),
    );

    _channel!.stream.listen(
      (message) {
        final data = json.decode(message);
        onMessageReceived?.call(data);
      },
      onError: (error) {
        debugPrint("WebSocket error: $error");
        onConnectionError?.call();
      },
      onDone: () {
        debugPrint("WebSocket connection closed.");
        onConnectionClosed?.call();
      },
    );
  }

  /// @brief Dispatches JSON-encoded payloads across the active WebSocket tunnel.
  /// @param message Key-value dictionary carrying the encoded payload mapping.
  void sendMessage(Map<String, dynamic> message) {
    if (_channel == null) {
      debugPrint("WebSocket is not connected.");
      return;
    }

    try {
      _channel!.sink.add(json.encode(message));
      debugPrint("Sent message: $message");
    } catch (e) {
      debugPrint("Error sending message: $e");
    }
  }

  /// @brief Forcefully shutters the open channel with a standard `goingAway` status code.
  void close() {
    _channel?.sink.close(status.goingAway);
  }
}
