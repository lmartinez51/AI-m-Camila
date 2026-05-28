// @file ai_voice_service.dart
// @brief Master contract interface for AI engine voice integrations.
// @author Lorenzo Martínez
// @date 2026-03-30
// @version 1.0.0

import 'dart:typed_data';

/// @brief Master contract interface for AI engine voice integrations connected to AI'm Camila.
abstract class AIVoiceService {
  // 👇 NUEVAS FIRMAS PARA LA SUTURA INVISIBLE si el socket se cae 👇
  /// @brief Verifies if the active WebSocket remains connected.
  bool get isConnected;

  /// @brief Injects spatial conversation context recovering from connection loss.
  /// @param contextStr Serialized semantic history data.
  void injectReconnectionContext(String contextStr);

  // --- CALLBACKS PÚBLICOS (El Provider los escucha) ---
  Function(dynamic)? onMessageReceived;
  Function(String)? onOutputAudioTranscriptReceived;
  Function(String)? onInputAudioTranscriptReceived;
  Function(Uint8List)? onAudioDeltaReceived;

  // IMPORTANTE: Este callback ahora debe entregar el audio FINAL,
  // ya protegido con WAV si el motor específico (como Gemini) lo requiere.
  Function(Uint8List)? onResponseDone;

  Function(dynamic)? onSpeechStarted; // Callback para interrupcion del chatbot
  Function()? onSpeechStopped;

  // Nuevo cable para avisar el estado de delegación a sub-agentes
  Function(bool isDelegating)? onDelegatingTask;

  // Nuevo cable para la despedida
  Function()? onEndConversationTriggered;
  
  // Nuevo cable para ejecutar comandos de la app (App Telekinesis)
  Function(String command)? onAppCommandTriggered;

  /// @brief Fires when the server closes the connection with a fatal, non-recoverable code
  /// (e.g. 1011 Quota Exceeded, 1008 Policy Violation). Implementors must NOT reconnect.
  Function()? onFatalErrorTriggered;

  // --- MÉTODOS PÚBLICOS (El Provider los llama) ---

  /// @brief Initiates WebSocket handshakes and active listeners.
  /// @return `Future<void>`
  Future<void> connect();

  /// @brief Safely drops current session RAM states and conversational context.
  void clearContext();

  /// @brief Terminates the active connection securely without leaking stream subscriptions.
  void closeConnection();

  /// @brief Pipes text and optional Base64 visual data directly into the active model logic loop.
  /// @param text Optional user query string.
  /// @param base64Image Optional encoded visual image.
  void sendUserMessageAndImage(String? text, String? base64Image);

  /// @brief Pushes a raw binary PCM audio payload dynamically into the engine.
  /// @param data Stream slice array holding raw audio bytes.
  void sendAudioChunk(Uint8List data);

  /// @brief Flags the engine to abruptly sever the AI's current outgoing voice generation hook.
  void cancelResponse();

  /// @brief Empties internal audio buffering queues or signals the model that the user chunk has terminated.
  void clearAudioBuffer();

  /// @brief Explicitly forces the UI state engine to hand the microphone turn back to the active model.
  void commitUserAudioTurn();

  /// @brief Función para inyectar comandos ocultos y forzar a la IA a hablar
  void triggerInvisibleResponse(String prompt);
}
