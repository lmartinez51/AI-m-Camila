// @file gemini_websocket_service.dart
// @brief Gemini Bidi websocket integration maintaining native VAD connections to Gemini 3.1 Flash Live.
// @author Lorenzo Martínez
// @date 2026-03-30
// @version 1.0.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:aimcamila/api/ai_voice_service.dart';
import 'package:aimcamila/api/gemini_tool_handler.dart';
import 'package:aimcamila/providers/user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:aimcamila/utils/ai_tools_registry.dart';
import 'package:aimcamila/utils/prompt_manager.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// @brief Implementation of `AIVoiceService` bridging the application directly to Google's BidiGenerateContent endpoint.
class GeminiWebSocketService with GeminiToolHandler implements AIVoiceService {
  final UserProvider _userProvider;

  // 1. SIN SINGLETON: Para que el Hot-Swap sea limpio.
  GeminiWebSocketService(this._userProvider);

  final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  late final String _url =
      "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=$apiKey";

  IOWebSocketChannel? _channel;

  @override
  bool get isConnected => _channel != null && _channel!.closeCode == null;

  // --- NUEVO: Cable para avisar a la UI sobre tareas externas ---
  @override
  Function(bool isDelegating)? onDelegatingTask;

  @override
  Function()? onEndConversationTriggered;

  @override
  Function(String command)? onAppCommandTriggered;

  @override
  void injectReconnectionContext(String contextStr) {
    // Para Gemini, el "contexto" es el mensaje de setup.
    // Simplemente nos aseguramos de que el próximo connect() lo reenvíe.
    // Como _sendSetupMessage() se llama en cada connect(), esto se cumple automáticamente.
    debugPrint("Gemini: Context injected (Setup message will be resent).");
  }

  @override
  void triggerInvisibleResponse(String prompt) {
    if (prompt.isEmpty || _channel == null || !isConnected) return;

    // As per Gemini 3.1 Live API docs:
    // 'mediaChunks' is DEPRECATED. We use the 'text' string field directly
    // inside 'realtimeInput' for real-time text streams.
    sendEvent({
      "realtimeInput": {"text": prompt}
    });

    debugPrint(
        "🥷 INVISIBLE INJECTION (GEMINI 3.1): Plain text injected via realtimeInput.text");
  }

  @override
  Function(dynamic)? onMessageReceived;
  @override
  Function(String)? onOutputAudioTranscriptReceived;
  @override
  Function(String)? onInputAudioTranscriptReceived;
  @override
  Function(Uint8List)? onAudioDeltaReceived;
  @override
  Function(Uint8List)? onResponseDone;
  @override
  Function(dynamic)? onSpeechStarted;
  @override
  Function()? onSpeechStopped;

  final List<Uint8List> _audioChunks = [];
  String _currentTranscript = "";
  String _currentUserTranscript = ""; // 👈 Para acumular tu voz

  // 2. BUFFER DE ESPERA: Para no saturar a Google antes de que nos dé luz verde.
  bool _isSetupComplete = false;
  final List<Uint8List> _preSetupAudioBuffer = [];

  // NUEVAS VARIABLES PARA CONTROL TOTAL
  bool _isConnecting = false;
  //bool _hasNotifiedSpeechStart = false;

  // 🚨 FATAL ERROR FLAG: Suppresses reconnection after server-side quota/policy violations.
  bool _isFatalError = false;

  @override
  Function()? onFatalErrorTriggered;

  @override
  Future<void> connect() async {
    _isFatalError =
        false; // Reset on every explicit connect so manual retries work.
    await _connectWebSocket();
  }

  // --- NUEVO: LIMPIEZA DE CONTEXTO ---
  @override
  void clearContext() {
    debugPrint("🧹 Limpiando contexto de la sesión (RAM de Gemini)...");

    // 1. Matamos la conexión actual (purga buffers y el canal IOWebSocket)
    closeConnection();

    // 2. Reconectamos inmediatamente. Al hacerlo, _sendSetupMessage()
    // se dispara automáticamente, inyectando la identidad fresca pero
    // sin el historial de la plática anterior.
    connect();

    debugPrint("✨ Contexto limpiado. WebSocket reiniciado en blanco.");
  }

  /// @brief Bootstraps the Gemini bidirectional stream and pushes initial configuration instructions.
  Future<void> _connectWebSocket() async {
    try {
      final uri = Uri.parse(_url);
      final webSocket = await WebSocket.connect(uri.toString());

      _channel = IOWebSocketChannel(webSocket);
      debugPrint("Connected to Gemini WebSocket server.");

      _sendSetupMessage();

      _channel!.stream.listen(
        (message) {
          String textMessage =
              message is List<int> ? utf8.decode(message) : message.toString();
          final data = json.decode(textMessage);

          // 🔇 EL SILENCIADOR ABSOLUTO (Mata el token antes de que se imprima y sature la RAM)
          if (data.containsKey('sessionResumptionUpdate')) return;

          if (!data.containsKey('serverContent') ||
              data['serverContent']['modelTurn'] == null) {
            debugPrint("Gemini WS Event: ${data.keys.first}");
          }

          _handleIncomingMessage(data);
        },
        onError: (error) {
          debugPrint("Gemini WebSocket closed (onError): $error");
          closeConnection(); // Blindaje 1
        },
        onDone: () {
          final closeCode = _channel?.closeCode;
          debugPrint(
              "ACCION: Gemini WebSocket connection closed (onDone). Code: $closeCode, Reason: ${_channel?.closeReason}");

          // 🚨 FATAL ERROR INTERCEPT: Codes 1011 (Quota Exceeded) and 1008 (Policy Violation)
          // are non-recoverable. Setting _isFatalError=true prevents any auto-reconnect loop.
          if (closeCode == 1011 || closeCode == 1008) {
            debugPrint(
                "🚨 FATAL SERVER ERROR (Code: $closeCode). Killing reconnection loop.");
            _isFatalError = true;
            closeConnection();
            onFatalErrorTriggered?.call();
            return;
          }

          closeConnection();
        },
      );
    } catch (e) {
      debugPrint("Error connecting to Gemini WS: $e");
    }
  }

  /// @brief The primary event router parsing tool calls, response boundaries, and text stream fragments.
  /// @param data JSON mapping representing Gemini's server payload.
  void _handleIncomingMessage(Map<String, dynamic> data) {
    try {
      onMessageReceived?.call(data);

      if (data.containsKey('setupComplete')) {
        _isSetupComplete = true;
        _flushPreSetupAudio();
      }

      if (data.containsKey('goAway')) {
        debugPrint("⚠️ Google envió 'goAway'. La sesión expiró.");
        closeConnection();
      }

      // 🛠️ 1. ATRAPAMOS LA LLAMADA A LA HERRAMIENTA (En la raíz del JSON)
      if (data.containsKey('toolCall')) {
        final functionCalls = data['toolCall']['functionCalls'] as List;
        for (var call in functionCalls) {
          handleGeminiFunctionCall(call);
        }
      }

      // 🛑 2. ATRAPAMOS LA CANCELACIÓN (Si el usuario interrumpe a Camila mientras busca)
      if (data.containsKey('toolCallCancellation')) {
        debugPrint(
            "🛑 [GEMINI LIVE] El servidor canceló la herramienta por interrupción del usuario.");
        onDelegatingTask?.call(false); // Liberamos la UI
      }

      if (data.containsKey('serverContent')) {
        final serverContent = data['serverContent'];

        // 🟢 1. CAPTURAMOS TU VOZ (Y TOCAMOS EL TIMBRE DE INICIO)
        if (serverContent.containsKey('inputTranscription')) {
          String userTextChunk =
              serverContent['inputTranscription']['text'] ?? "";
          if (userTextChunk.isNotEmpty) {
            // Si el buffer está vacío, significa que es tu primera sílaba.
            // Avisamos a la UI para que pinte la burbuja "en blanco".
            if (_currentUserTranscript.isEmpty) {
              onSpeechStarted?.call("user");
            }
            // Acumulamos los fragmentos de tu frase
            _currentUserTranscript += userTextChunk;
          }
        }

        // 🟢 2. DISPARAMOS TU BURBUJA (Y TOCAMOS EL TIMBRE DE FIN)
        // Si el servidor nos manda el turno del modelo, tú ya terminaste de hablar.
        if (serverContent.containsKey('modelTurn') ||
            serverContent.containsKey('outputTranscription')) {
          if (_currentUserTranscript.isNotEmpty) {
            // Avisamos a la UI que ya te callaste para que selle la burbuja
            onSpeechStopped?.call();

            debugPrint(
                "🗣️ TEXTO DEL USUARIO: ${_currentUserTranscript.trim()}");
            // Rellenamos la burbuja con el texto
            onInputAudioTranscriptReceived?.call(_currentUserTranscript.trim());
            _currentUserTranscript = ""; // Limpiamos para tu siguiente turno
          }
        }

        // 🟢 3. CAPTURAMOS EL TEXTO DE CAMILA
        if (serverContent.containsKey('outputTranscription')) {
          String textChunk = serverContent['outputTranscription']['text'] ?? "";
          if (textChunk.isNotEmpty) {
            _currentTranscript += textChunk;
          }
        }

        // 🟢 4. CAPTURAMOS EL TURNO DE CAMILA
        if (serverContent.containsKey('modelTurn')) {
          final parts = serverContent['modelTurn']['parts'] as List;
          for (var part in parts) {
            if (part.containsKey('inlineData')) {
              _handleAudioDelta(part['inlineData']['data']);
            }
            if (part.containsKey('text')) {
              String newText = part['text'];
              if (!newText.startsWith('**') && !newText.startsWith('[')) {
                _currentTranscript += newText;
              }
            }
            // 🛠️ ¡AQUÍ REDIRIGIMOS EL LLAMADO A NUESTRA NUEVA FUNCIÓN!
            if (part.containsKey('functionCall')) {
              handleGeminiFunctionCall(part['functionCall']);
            }
          }
        }

        // 🟢 5. FIN DEL TURNO DE CAMILA
        if (serverContent.containsKey('turnComplete') &&
            serverContent['turnComplete'] == true) {
          if (_currentTranscript.trim().isNotEmpty) {
            debugPrint("✅ TEXTO DE CAMILA: ${_currentTranscript.trim()}");
            onOutputAudioTranscriptReceived?.call(_currentTranscript.trim());
            _currentTranscript = "";
          }
          _handleAudioDone();
          //_hasNotifiedSpeechStart = false; // Reiniciamos el semáforo
        }

        if (serverContent.containsKey('interrupted') &&
            serverContent['interrupted'] == true) {
          debugPrint("🛑 Interrupción detectada. Purificando buffers...");
          _audioChunks.clear();
          _currentTranscript = "";
          _currentUserTranscript = ""; // Limpiamos tu frase a medias
          onSpeechStarted?.call("user_interruption");
        }
      }
    } catch (e) {
      debugPrint("Error handling incoming Gemini message: $e");
    }
  }

  @override

  /// @brief Defers audio into emergency buffers during handshakes or pipes it immediately to Gemini PCM boundaries.
  /// @param data The raw microphone slice array.
  void sendAudioChunk(Uint8List data) {
    // AUTO-RECONECTAR POR VOZ
    if (_channel == null || _channel!.closeCode != null) {
      if (_isFatalError) {
        return; // 🛑 Never auto-reconnect after a fatal server error.
      }
      _preSetupAudioBuffer.add(data);
      if (!_isConnecting) {
        _isConnecting = true;
        debugPrint("🔄 Socket cerrado por voz. Reconectando...");
        connect().then((_) => _isConnecting = false);
      }
      return;
    }

    if (!_isSetupComplete) {
      _preSetupAudioBuffer.add(data);
      return;
    }
    _sendRealtimeAudio(data);
  }

  /// @brief Drains audio collected prior to Google transmitting the `setupComplete` acknowledgment.
  void _flushPreSetupAudio() {
    if (_preSetupAudioBuffer.isNotEmpty) {
      for (var chunk in _preSetupAudioBuffer) {
        _sendRealtimeAudio(chunk);
      }
      _preSetupAudioBuffer.clear();
      debugPrint(
          "🚀 Buffer de audio de pre-configuración vaciado al servidor.");
    }
  }

  /// @brief Safely encodes PCM segments to Base64 and builds the explicit `realtimeInput` dictionary.
  /// @param data Audio array slice.
  void _sendRealtimeAudio(Uint8List data) {
    if (data.isEmpty) return; // 🛡️ Escudo anti-1007 para audios vacíos

    sendEvent({
      "realtimeInput": {
        // 🚀 EL FIX FINAL: Quitamos los corchetes [ ]. Es un objeto directo.
        "audio": {
          "mimeType": "audio/pcm;rate=24000",
          "data": base64Encode(data)
        }
      }
    });
  }

  /// @brief Pulls returning response voice generation and cues the UI UI tracking variables.
  /// @param base64Audio The Base64 string payload holding the slice of audio.
  void _handleAudioDelta(String base64Audio) {
    try {
      final decodedAudio = base64Decode(base64Audio);
      onAudioDeltaReceived?.call(decodedAudio);
      _audioChunks.add(decodedAudio);
    } catch (e) {
      debugPrint("Error decoding Gemini audio delta: $e");
    }
  }

  /// @brief Utility transforming raw PCM bytes returned by Gemini into a valid WAV format the media player accepts.
  /// @param rawAudio Pure concatenated data points.
  /// @return `Uint8List` Wrapper array combining the header and data.
  Uint8List _addWavHeader(Uint8List rawAudio) {
    int channels = 1;
    int sampleRate = 24000;
    int byteRate = sampleRate * channels * 2;
    int totalDataLen = rawAudio.length + 36;
    int audioDataLen = rawAudio.length;

    var header = ByteData(44);
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, totalDataLen, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, audioDataLen, Endian.little);

    var builder = BytesBuilder();
    builder.add(header.buffer.asUint8List());
    builder.add(rawAudio);
    return builder.toBytes();
  }

  /// @brief Condenses delta arrays, signs them with WAV headers, and executes playback completion listeners.
  void _handleAudioDone() {
    if (_audioChunks.isNotEmpty) {
      try {
        Uint8List rawAudio =
            Uint8List.fromList(_audioChunks.expand((chunk) => chunk).toList());
        Uint8List safeWavAudio = _addWavHeader(rawAudio);
        onResponseDone?.call(safeWavAudio);
        _audioChunks.clear();
      } catch (e) {
        debugPrint("Error handling Gemini audio done: $e");
      }
    }
  }

  // 3. LA JOYA: SETUP MIGRADO A GEMINI 3.1 FLASH LIVE (VERSIÓN LIMPIA)
  /// @brief Configures Gemini 3.1 Flash Live explicitly sending the Persona system prompt and all available OpenApi Tool definitions.
  void _sendSetupMessage() {
    try {
      final user = _userProvider.user!;
      final systemInstructions = PromptManager.getSessionUpdateInstructions(
        fullName: user.name,
        nickname: user.nickname,
        personalBackground: user.personalBackground,
        interests: user.interests,
        relationship: user.relationship,
      );

      sendEvent({
        "setup": {
          "model": "models/gemini-3.1-flash-live-preview",
          "systemInstruction": {
            "parts": [
              {"text": systemInstructions}
            ]
          },
          "outputAudioTranscription": {},
          "inputAudioTranscription": {},
          "generationConfig": {
            "responseModalities": ["AUDIO"],
            "thinkingConfig": {"thinkingLevel": "minimal"},
            "speechConfig": {
              "voiceConfig": {
                "prebuiltVoiceConfig": {"voiceName": "Callirrhoe"}
              }
            }
          },
          // 🛠️ LA INYECCIÓN DE HERRAMIENTAS (Via AiToolsRegistry — Single Source of Truth)
          "tools": [
            //{"googleSearch": {}},
            {"functionDeclarations": AiToolsRegistry.geminiDeclarations}
          ]
        }
      });
      debugPrint("🚀 [GeminiLive] Setup limpio de v3.1 enviado con éxito.");
    } catch (e) {
      debugPrint("Error sending Gemini setup: $e");
    }
  }

  /// @brief Safe pipeline for pushing fully parsed JSON strings down the `IOWebSocketChannel`.
  /// @param event Object map of parameters to encode.
  @override
  void sendEvent(Map<String, dynamic> event) {
    try {
      if (_channel == null || _channel!.closeCode != null) return;
      _channel!.sink.add(json.encode(event));
    } catch (e) {
      debugPrint("Error sending Gemini event: $e");
    }
  }

  // 4. EL GATILLO NEUTRALIZADO: Dejamos que Gemini use su propio VAD.
  @override
  void commitUserAudioTurn() {
    debugPrint("Gemini usa VAD nativo, ignorando commit manual.");
  }

  @override
  void cancelResponse() {
    // 🧹 LIMPIEZA EXTREMA: Vaciamos cualquier residuo fantasma antes de cancelar
    _audioChunks.clear();
    _currentTranscript = "";

    sendEvent({
      "clientContent": {
        "turns": [
          {
            "role": "user",
            "parts": [
              {"text": ""}
            ]
          }
        ],
        "turnComplete": true
      }
    });
    debugPrint("🛑 ACCION: Respuesta de Gemini cancelada (Buffers limpios).");
  }

  @override
  void clearAudioBuffer() {
    _audioChunks.clear();
    _currentTranscript = "";
    debugPrint("🧹 ACCION: Buffer de audio local purgado con éxito.");
  }

  @override
  void closeConnection() {
    try {
      // 🚨 GUILLOTINE SIGNAL: Fire response done to unlock UI safely during clear_chat
      if (_audioChunks.isNotEmpty) {
        _handleAudioDone(); // Purge any remaining partial responses
      } else {
        // Send a blank 0-byte buffer to guarantee AudioStreamProvider resets its UI
        onResponseDone?.call(Uint8List(0));
      }

      _currentTranscript = "";

      _channel?.sink.close();
      _channel = null; // ☠️ ESTO ES VITAL PARA LA RECONEXIÓN
      _isSetupComplete = false;
      //_hasNotifiedSpeechStart = false;
      // 🛡️ BLINDAJE ANTI-FUGAS DE MEMORIA: Purga el buffer de emergencia
      _preSetupAudioBuffer.clear();
      //debugPrint("Gemini WebSocket connection closed.");
    } catch (e) {
      debugPrint("Error closing Gemini connection: $e");
    }
  }

  @override

  /// @brief Generates atomic `clientContent` payloads wrapping visual data and manual text overwrites over WebSocket.
  /// @param text Optional text prompt.
  /// @param base64Image Properly formatted Base64 array string for model analysis.
  void sendUserMessageAndImage(String? text, String? base64Image) async {
    try {
      if (_channel == null || _channel!.closeCode != null) {
        if (_isFatalError) {
          debugPrint(
              "🚨 Socket cerrado por error fatal. Abortando envío de mensaje.");
          return;
        }
        debugPrint("🔄 Socket cerrado. Reconectando automáticamente...");
        await connect();
        // Le damos un poco más de tiempo para que el Setup se complete tras reconectar
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      bool hasImage = base64Image != null && base64Image.isNotEmpty;
      bool hasText = text != null && text.trim().isNotEmpty;

      List<Map<String, dynamic>> parts = [];

      // 1. EL TEXTO (Con seguro anti-mimos)
      String textToSend = text ?? "";
      if (hasImage && !hasText) {
        // Si mandas foto sin escribir nada, la obligamos a reaccionar
        textToSend = "Aquí tienes la imagen.";
      }

      if (textToSend.isNotEmpty) {
        parts.add({"text": textToSend});
      }

      // 2. LA IMAGEN (Empaquetada para viajar junto al texto)
      if (hasImage) {
        String cleanBase64 = base64Image;
        String mimeType = "image/jpeg";

        if (base64Image.contains(',')) {
          final split = base64Image.split(',');
          cleanBase64 = split.last;
          final header = split.first;
          final mimeMatch = RegExp(r'data:(.*?);').firstMatch(header);
          if (mimeMatch != null) mimeType = mimeMatch.group(1) ?? "image/jpeg";
        }
        cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');

        parts.add({
          "inlineData": {"mimeType": mimeType, "data": cleanBase64}
        });
      }

      // 3. EL ENVÍO ATÓMICO (Todo en el mismo turno)
      if (parts.isNotEmpty) {
        sendEvent({
          "clientContent": {
            "turns": [
              {"role": "user", "parts": parts}
            ],
            "turnComplete": true
          }
        });
        debugPrint(
            "📸💬 Envío atómico realizado (Partes combinadas: ${parts.length})");
      }
    } catch (e) {
      debugPrint("Error al enviar multimedia a Gemini: $e");
    }
  }

  // 🛠️ Tool execution is now handled by GeminiToolHandler mixin.
  // See: lib/api/gemini_tool_handler.dart
}
