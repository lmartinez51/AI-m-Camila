// @file openai_realtime_api.dart
// @brief WebSockets manager implementing Realtime API v1.5 with advanced audio VAD logic and memories.
// @author Lorenzo Martínez
// @date 2026-03-30
// @version 1.0.0

import 'dart:convert';
import 'dart:io';
import 'package:aimcamila/api/openai_tool_handler.dart';
import 'package:aimcamila/database/objectbox_service.dart';
import 'package:aimcamila/models/episodic_memory.dart';
import 'package:aimcamila/models/semantic_memory.dart';
import 'package:aimcamila/providers/user_provider.dart';
import 'package:aimcamila/api/ai_voice_service.dart';
import 'package:aimcamila/utils/ai_tools_registry.dart';
import 'package:aimcamila/utils/prompt_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// @brief Implementation of `AIVoiceService` controlling OpenAI's Realtime voice and text streams.
class WebSocketService with OpenAiToolHandler implements AIVoiceService {
  final UserProvider _userProvider;
  WebSocketService(this._userProvider);

  @override
  final String apiKey = dotenv.env['OPENAI_API_NEW_KEY'] ?? '';
  final String _url = "wss://api.openai.com/v1/realtime?model=gpt-realtime-2";
  IOWebSocketChannel? _channel;

  // Acumula lo que vas diciendo en tiempo real
  String _liveTranscriptBuffer = '';
  // Usa un 'Set' en lugar de 'List' para no guardar el mismo apunte 20 veces si repites una palabra
  final Set<String> _preWarmedContexts = {};

  @override
  Function(bool isDelegating)? onDelegatingTask;

  @override
  Function()? onEndConversationTriggered;

  @override
  Function(String command)? onAppCommandTriggered;

  /// @brief Stub: OpenAI Realtime API does not issue fatal quota close codes.
  /// Declared here to satisfy the [AIVoiceService] abstract contract.
  @override
  Function()? onFatalErrorTriggered;

  @override
  bool get isConnected => _channel != null;

  @override
  void injectReconnectionContext(String contextStr) {
    if (contextStr.isEmpty || _channel == null) return;

    // 🥷 EL PROMPT NINJA DE SUTURA
    final prompt =
        "[Internal Recall: The network briefly disconnected. You remember the recent conversation was about: $contextStr. Continue naturally as if no interruption occurred.]";

    sendEvent({
      "type": "conversation.item.create",
      "item": {
        "type": "message",
        "role": "system",
        "content": [
          {"type": "input_text", "text": prompt}
        ]
      }
    });
    debugPrint(
        "🥷 SUTURA INVISIBLE: Contexto reciente inyectado exitosamente.");
  }

  @override
  Function(dynamic)? onMessageReceived;
  @override
  Function(String)?
      onOutputAudioTranscriptReceived; // Callback para manejar el transcript
  @override
  Function(String)? onInputAudioTranscriptReceived;
  @override
  Function(Uint8List)?
      onAudioDeltaReceived; // Callback para manejar audio delta
  // Function()?
  //     onInputAudioCommitted; // Callback para manejar input audio committed
  @override
  Function(Uint8List)? onResponseDone; // Callback para manejar response.done
  @override
  Function(dynamic)?
      onSpeechStarted; // Callback para manejar la interrupcion del chatbot
  @override
  Function()? onSpeechStopped; // Callback para silenciar el mic
  final List<Uint8List> _audioChunks =
      []; // Lista para acumular fragmentos de audio
  bool _sessionUpdated =
      false; // Bandera para rastrear si session.update ya se envió

  @override
  Future<void> connect() async {
    await _connectWebSocket();
  }

  // --- NUEVO: LIMPIEZA DE CONTEXTO (OPENAI) ---
  @override
  void clearContext() {
    debugPrint("🧹 Limpiando contexto de la sesión (RAM de OpenAI)...");

    // 1. Limpiamos los buffers locales de escucha activa
    _liveTranscriptBuffer = '';
    _preWarmedContexts.clear();

    // 2. Matamos la conexión actual (purga el canal y resetea las banderas)
    closeConnection();

    // 3. Reconectamos inmediatamente. Esto disparará _sendSessionUpdateOnce()
    // y _injectEpisodicMemoryOnStartup() en un lienzo limpio.
    connect();

    debugPrint(
        "✨ Contexto limpiado. WebSocket de OpenAI reiniciado en blanco.");
  }

  @override
  void triggerInvisibleResponse(String prompt) {
    if (prompt.isEmpty || _channel == null || !isConnected) return;

    // 1. Inyectamos la instrucción limpia (sin hardcodes raros)
    sendEvent({
      "type": "conversation.item.create",
      "item": {
        "type": "message",
        "role": "system",
        "content": [
          {"type": "input_text", "text": prompt}
        ]
      }
    });

    // 2. 🚀 EL GATILLO OBLIGATORIO: Fuerza a la IA a generar audio ya mismo
    sendEvent({"type": "response.create"});

    debugPrint("🥷 INYECCIÓN INVISIBLE: Estímulo enviado y respuesta forzada.");
  }

  /// @brief Bootstraps the WSS connection to OpenAI sending authorization and early memory injections.
  Future<void> _connectWebSocket() async {
    try {
      final uri = Uri.parse(_url);
      final webSocket = await WebSocket.connect(uri.toString(),
          headers: {"Authorization": "Bearer $apiKey"});

      _channel = IOWebSocketChannel(webSocket);
      debugPrint("Connected to WebSocket server.");

      _sendSessionUpdateOnce(); // Asegurarse de enviar session.update solo una vez
      _injectEpisodicMemoryOnStartup(); // Inyectar la memoria episódica al inicio

      _channel!.stream.listen(
        (message) {
          final data = json.decode(message);
          // FILTRO PROFESIONAL: Ignoramos el spam visual de los deltas
          // 🟢 NOMBRES ACTUALIZADOS PARA GA:
          if (data['type'] != 'response.output_audio.delta' &&
              data['type'] != 'response.output_audio_transcript.delta') {
            // Imprimimos el tipo de evento para saber qué está haciendo el WebSocket
            debugPrint("WebSocket Event: ${data['type']}");

            // Si hay un error, lo imprimimos completo
            if (data['type'] == 'error') {
              debugPrint("OpenAI Error Details: $data");
            }
          }

          _handleIncomingMessage(data);
        },
        onError: (error) {
          debugPrint("WebSocket error: $error");
        },
        onDone: () {
          debugPrint("WebSocket connection closed naturally or by OS.");
          _channel = null; // 👈 CRUCIAL: Esto le avisa al sistema que morimos
          _sessionUpdated =
              false; // 👈 CRUCIAL: Obliga a mandar tus instrucciones de nuevo al reconectar
        },
      );
    } catch (e) {
      debugPrint("Error connecting to WebSocket server: $e");
    }
  }

  // 3. MÉTODO PARA ENVIAR AUDIO (Esto antes vivía en tu Provider)
  @override

  /// @brief Dispatches hardware mic telemetry up to the active OpenAi VAD model.
  /// @param data The slice of PCM data collected from the UI.
  void sendAudioChunk(Uint8List data) {
    sendEvent({
      "type": "input_audio_buffer.append",
      "audio": base64Encode(data),
    });
  }

  // 4. COMPATIBILIDAD DE INTERFAZ (OpenAI usa un comando distinto para forzar el turno)
  @override

  /// @brief Signals an end to microphone transmission forcing OpenAI to evaluate the incoming context blocks.
  void commitUserAudioTurn() {
    // 🛡️ ANULADO: En GA, mandar un commit vacío crashea el audio.
    // Dejamos que el semantic_vad del servidor haga todo el trabajo.
    //sendEvent({"type": "input_audio_buffer.commit"});
    debugPrint("Turno de audio delegado al VAD Semántico del servidor.");
  }

  /// @brief Top-level Demultiplexer classifying dynamic WebSockets JSON maps.
  /// @param data Single raw server tick output.
  void _handleIncomingMessage(Map<String, dynamic> data) {
    try {
      // Manejo de los mensajes en general
      onMessageReceived?.call(data);

      switch (data['type']) {
        case 'response.output_audio.delta':
          if (data['delta'] != null) {
            _handleAudioDelta(data);
          }
          break;
        case 'response.audio.done':
        case 'response.output_audio.done':
          _handleAudioDone();
          break;
        case 'response.done':
          _handleResponseDone(data);
          break;
        // case 'input_audio_buffer.committed':
        //   _handleInputAudioBufferCommitted(data);
        //   break;
        case 'input_audio_buffer.speech_started':
          _handleSpeechStarted(data);
          break;
        case 'input_audio_buffer.speech_stopped':
          _handleSpeechStopped(data);
          break;
        case 'response.function_call_arguments.done':
          handleFunctionCallArgumentsDone(data);
          break;
        case 'conversation.item.input_audio_transcription.completed':
          _handleTranscriptionCompleted(data);
          break;
        case 'conversation.item.input_audio_transcription.delta':
          _handleTranscriptionDelta(data);
          break;
      }
    } catch (e) {
      debugPrint("Error handling incoming message: $e");
    }
  }

  /// @brief Reads incoming text stream bits searching local ObjectBox context dynamically.
  /// @param data WebSockets packet.
  void _handleTranscriptionDelta(Map<String, dynamic> data) {
    try {
      final deltaText = data['delta']?.toString().toLowerCase() ?? '';
      if (deltaText.isEmpty) return;

      // 1. Acumulamos la palabra o sílaba que acaba de llegar
      _liveTranscriptBuffer += deltaText;

      // 2. Buscamos en la base de datos con lo que llevamos hasta ahora
      final box = objectbox.store.box<SemanticMemory>();
      final allMemories = box.getAll();

      for (var memory in allMemories) {
        final searchString =
            "${memory.category} ${memory.content}".toLowerCase();
        final searchWords = searchString.split(RegExp(r'\s+'));

        bool hasMatch = searchWords.any((word) {
          if (word.length <= 3) return false;
          return _liveTranscriptBuffer.contains(word);
        });

        if (hasMatch) {
          // Si hace match, lo guardamos en el Set (el Set ignora duplicados automáticamente)
          _preWarmedContexts.add("${memory.category}: ${memory.content}");
        }
      }
    } catch (e) {
      debugPrint("Error en Escolta Delta: $e");
    }
  }

  /// @brief Reads final semantic chunks evaluating tool states and injecting gathered ObjectBox vectors.
  /// @param data WebSockets packet.
  void _handleTranscriptionCompleted(Map<String, dynamic> data) {
    try {
      // 1. 🥷 EXTRAEMOS LA TRANSCRIPCIÓN REAL DEL USUARIO
      final userTranscript = data['transcript'];
      if (userTranscript != null && onInputAudioTranscriptReceived != null) {
        debugPrint("🗣️ [User]: $userTranscript");
        // Mandamos el texto a la UI para que lo inyecte en secreto
        onInputAudioTranscriptReceived!(userTranscript);
      }

      // 2. Si el Escolta Delta encontró algo mientras hablabas, lo inyectamos YA
      if (_preWarmedContexts.isNotEmpty) {
        final contextString =
            "[Internal Recall: Relevant factual data retrieved regarding the current topic: ${_preWarmedContexts.join(', ')}]";

        debugPrint(
            "⚡ RAG ULTRA-RÁPIDO: Inyectando contexto pre-calentado: ${_preWarmedContexts.join(', ')}");

        sendEvent({
          "type": "conversation.item.create",
          "item": {
            "type": "message",
            "role": "system",
            "content": [
              {"type": "input_text", "text": contextString}
            ]
          }
        });
      }

      // 3. Limpiamos la memoria de trabajo para tu siguiente frase
      _liveTranscriptBuffer = '';
      _preWarmedContexts.clear();
    } catch (e) {
      debugPrint("Error en Escolta Completed: $e");
    }
  }

  /// @brief Traps the `done` packet scanning for output text and audio markers.
  /// @param data WebSockets packet.
  void _handleResponseDone(Map<String, dynamic> data) {
    try {
      final output = data['response']['output'];
      if (output != null && output is List) {
        for (var item in output) {
          if (item['content'] != null && item['content'] is List) {
            for (var contentBlock in item['content']) {
              if (contentBlock['type'] == 'transcript' ||
                  contentBlock['transcript'] != null) {
                final transcript = contentBlock['transcript'] as String?;
                if (transcript != null && transcript.isNotEmpty) {
                  onOutputAudioTranscriptReceived?.call(transcript);
                }
                debugPrint("🗣️ [Camila]: $transcript");
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error handling response done: $e");
    }
  }

  // void _handleInputAudioBufferCommitted(Map<String, dynamic> data) {
  //   try {
  //     debugPrint("Input audio buffer committed: $data");
  //     onInputAudioCommitted?.call(); // Llamar al callback si está definido
  //   } catch (e) {
  //     debugPrint("Error handling input audio buffer committed: $e");
  //   }
  // }

  /// @brief Server hook indicating user voice was captured.
  /// @param data JSON mapping.
  void _handleSpeechStarted(Map<String, dynamic> data) {
    // Añadir esta función
    try {
      debugPrint("Speech started event: $data");
      final itemId = data['item_id'];
      onSpeechStarted?.call(itemId); // Llamar al callback si está definido
    } catch (e) {
      debugPrint("Error handling speech started: $e");
    }
  }

  /// @brief Server hook indicating user voice stopped.
  /// @param data JSON mapping.
  void _handleSpeechStopped(Map<String, dynamic> data) {
    // Añadir esta función
    try {
      debugPrint("Speech stopped event: $data");
      onSpeechStopped?.call(); // Llamar al callback si está definido
    } catch (e) {
      debugPrint("Error handling speech stopped: $e");
    }
  }

  /// @brief Collects incoming assistant audio delta chunks.
  /// @param data Dynamic mapping containing base64 data.
  void _handleAudioDelta(dynamic data) {
    final delta = data['delta'];
    try {
      final decodedAudio = base64Decode(delta);

      // Envía el fragmento decodificado inmediatamente
      if (onAudioDeltaReceived != null) {
        onAudioDeltaReceived!(decodedAudio);
      }

      // Acumula el fragmento recibido solo si es necesario para otros propósitos
      _audioChunks.add(decodedAudio);
    } catch (e) {
      debugPrint("Error decoding audio delta: $e");
    }
  }

  /// @brief Compiles collected chunks into unified UI playable payloads.
  void _handleAudioDone() {
    debugPrint(
        "Audio playback completed. Total chunks recibidos: ${_audioChunks.length}");
    // Unir todos los fragmentos en un único buffer
    if (_audioChunks.isNotEmpty) {
      try {
        Uint8List fullAudio =
            Uint8List.fromList(_audioChunks.expand((chunk) => chunk).toList());

        // Llamar al callback si está definido
        if (onResponseDone != null) {
          onResponseDone!(fullAudio);
        }

        // Vaciar los fragmentos acumulados
        _audioChunks.clear();
      } catch (e) {
        debugPrint("Error handling audio done: $e");
      }
    }
  }

  /// Envía la actualización de la sesión solo una vez
  /// @brief Runs session parameter overwrites using cached locks.
  void _sendSessionUpdateOnce() {
    try {
      if (!_sessionUpdated) {
        _sendSessionUpdate();
        _sessionUpdated = true;
        debugPrint("Session updated successfully.");
      } else {
        debugPrint("Session update already sent. Skipping.");
      }
    } catch (e) {
      debugPrint("Error sending session update: $e");
    }
  }

  /// @brief Updates active server state passing System Instructions and tools metadata definitions (Tools Schema).
  void _sendSessionUpdate() {
    try {
      final user = _userProvider.user!;
      // Llamamos a nuestro nuevo Manager
      final systemInstructions = PromptManager.getSessionUpdateInstructions(
        fullName: user.name,
        nickname: user.nickname,
        personalBackground: user.personalBackground,
        interests: user.interests,
        relationship: user.relationship,
      );

      sendEvent({
        "type": "session.update",
        "session": {
          "type": "realtime",
          "model": "gpt-realtime-2",
          "output_modalities": ["audio"],
          "instructions": systemInstructions,
          // 🟢 LA NUEVA ANATOMÍA DE AUDIO EN GA
          "audio": {
            "input": {
              "format": {"type": "audio/pcm", "rate": 24000},
              // Filtro de ruido para celulares
              "noise_reduction": {"type": "near_field"},
              "transcription": {
                // 🚀 Downgrade to "whisper-1" for better performance (spanish)
                "model": "whisper-1",
                "language": "es"
              },
              // El detector de turnos ahora vive aquí adentro:
              "turn_detection": {
                "type": "semantic_vad",
              }
            },
            "output": {
              "format": {"type": "audio/pcm", "rate": 24000},
              "voice": "coral"
            }
          },
          // 🛠️ LA INYECCIÓN DE HERRAMIENTAS (Via AiToolsRegistry — Single Source of Truth)
          "tools": AiToolsRegistry.openAiTools,
          "tool_choice": "auto",
        }
      });
    } catch (e) {
      debugPrint("Error sending session update: $e");
    }
  }

  /// @brief Safe pipeline dispatching events to OpenAI channel.
  /// @param event Map of variables representing an OpenAI payload.
  @override
  void sendEvent(Map<String, dynamic> event) {
    try {
      if (_channel == null || _channel!.closeCode != null) {
        debugPrint("WebSocket is not connected or has been closed.");
        return;
      }
      _channel!.sink.add(json.encode(event));
    } catch (e) {
      debugPrint("Error sending event: $e");
    }
  }

  // 🧠 INYECCIÓN DE ARRANQUE: Alimenta a Camila con los últimos días
  /// @brief Scrapes local DB for recent memory events firing hidden system prompts to update conversational context.
  void _injectEpisodicMemoryOnStartup() {
    try {
      final box = objectbox.store.box<EpisodicMemory>();
      final allMemories = box.getAll();

      if (allMemories.isEmpty) {
        debugPrint(
            "🧠 DESAYUNO MENTAL: No hay memorias episódicas previas. Arrancando en blanco.");
        return;
      }

      // Ordenamos cronológicamente (las más viejas primero) para que la IA entienda la línea de tiempo
      allMemories.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      String contextBuilder =
          "[Internal Recall: You remember the following summary of recent interactions:\n";
      for (var m in allMemories) {
        final dateStr = m.createdAt.toIso8601String().split('T')[0];
        contextBuilder += "- Date: $dateStr | Summary: ${m.summary}\n";
      }
      contextBuilder += "]";

      // Lo inyectamos silenciosamente como un evento de sistema
      sendEvent({
        "type": "conversation.item.create",
        "item": {
          "type": "message",
          "role": "system",
          "content": [
            {"type": "input_text", "text": contextBuilder}
          ]
        }
      });
      debugPrint(
          "🧠 DESAYUNO MENTAL: Memoria de los últimos ${allMemories.length} días inyectada exitosamente.");
    } catch (e) {
      debugPrint("Error inyectando memoria de arranque: $e");
    }
  }

  // NUEVA FUNCIÓN: Destruye el buffer de audio del servidor para evitar respuestas fantasma
  @override

  /// @brief Neutrals the VAD buffer stopping phantom echo queues from executing.
  void clearAudioBuffer() {
    sendEvent({"type": "input_audio_buffer.clear"});
    debugPrint("Buffer de audio del servidor limpiado (VAD neutralizado).");
  }

  // NUEVA FUNCIÓN: Detiene inmediatamente la generación/transmisión de la respuesta del servidor
  @override

  /// @brief Actuates emergency server halt on active OpenAI text-generation trees.
  void cancelResponse() {
    sendEvent({"type": "response.cancel"});
    debugPrint(
        "Respuesta del servidor cancelada (Freno de emergencia activado).");
  }

  // 🛠️ Tool execution is now handled by OpenAiToolHandler mixin.
  // See: lib/api/openai_tool_handler.dart

  @override

  /// @brief Destroys `IOWebSocketChannel` and clears all references cleanly.
  void closeConnection() {
    try {
      _channel?.sink.close();
      _channel = null;
      _sessionUpdated = false;
      debugPrint("WebSocket connection closed.");
    } catch (e) {
      debugPrint("Error closing WebSocket connection: $e");
    }
  }

  // NUEVA FUNCIÓN: Envía texto e imágenes al túnel y dispara la respuesta
  @override

  /// @brief Directly formats specific message nodes adding optional vision layers.
  /// @param text Text value snippet to send.
  /// @param base64Image Encoded content slice.
  void sendUserMessageAndImage(String? text, String? base64Image) {
    try {
      List<Map<String, dynamic>> contentList = [];

      // 1. Agregamos el bloque de texto si existe
      if (text != null && text.isNotEmpty) {
        contentList.add({"type": "input_text", "text": text});
      }

      // 2. Agregamos el bloque de imagen si existe
      if (base64Image != null && base64Image.isNotEmpty) {
        // Aseguramos que el prefijo esté presente
        String finalBase64Url = base64Image.startsWith('data:image')
            ? base64Image
            : 'data:image/jpeg;base64,$base64Image';

        contentList.add({"type": "input_image", "image_url": finalBase64Url});
      }

      if (contentList.isEmpty) return; // Prevención: No enviar eventos vacíos

      // 3. Inyectamos la imagen/texto en la memoria de Camila
      sendEvent({
        "type": "conversation.item.create",
        "item": {"type": "message", "role": "user", "content": contentList}
      });

      // 4. EL GATILLO: Le decimos a Camila que responda a lo que le acabamos de mandar
      sendEvent({"type": "response.create"});

      debugPrint("Multimedia enviada al WebSocket exitosamente.");
    } catch (e) {
      debugPrint("Error al enviar mensaje multimedia por WebSocket: $e");
    }
  }
}
