import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:aimcamila/api/openai_api.dart';
import 'package:aimcamila/api/openai_responses_service.dart';
import 'package:aimcamila/database/objectbox_service.dart';
import 'package:aimcamila/models/episodic_memory.dart';
import 'package:aimcamila/utils/prompt_manager.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int maxChatHistoryLength = 10;

class Model with ChangeNotifier {
  /// Local state fields for this component.
  ValueNotifier<List<Map<String, dynamic>>> camilaChatHistory =
      ValueNotifier([]);
  ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  bool isWipingMemory = false; // 🔒 UI Quarantine Lock for tear-downs
  final audioPlayer = AudioPlayer();
  final record = AudioRecorder();
  final ScrollController listViewController = ScrollController();
  final FocusNode textFieldFocusNode = FocusNode();
  final FocusNode secondaryTextFieldFocusNode = FocusNode();
  final TextEditingController textController = TextEditingController();
  final openAIService = OpenAIService();
  String? Function(BuildContext, String?)? textControllerValidator;

  Future<PermissionStatus> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status;
  }

  // Método para guardar el historial del chat
  Future<void> saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('camilaChatHistory', jsonEncode(camilaChatHistory.value));
  }

  // Método para cargar el historial del chat
  Future<void> loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final camilaChatHistoryString = prefs.getString('camilaChatHistory');

    if (camilaChatHistoryString != null) {
      final List<Map<String, dynamic>> loadedHistory =
          List<Map<String, dynamic>>.from(jsonDecode(camilaChatHistoryString));

      // 🧠 MEJORA: No sobreescribimos los mensajes vivos que ya existan en la sesión.
      // Fusionamos lo cargado de disco con lo que esté en memoria actual.
      final currentMemoryHistory = camilaChatHistory.value;

      // Si ya hay mensajes en memoria (mensajes en vivo), los preservamos al final.
      // Primero la historia vieja, luego la nueva.
      final List<Map<String, dynamic>> mergedHistory = [
        ...loadedHistory,
        ...currentMemoryHistory
      ];

      // Eliminamos duplicados por contenido/rol para evitar eco visual tras navegar
      final seenMessages = <String>{};
      final uniqueHistory = mergedHistory.where((msg) {
        final content = msg['content'].toString();
        final role = msg['role'].toString();
        final key = "$role|$content";
        if (seenMessages.contains(key)) return false;
        seenMessages.add(key);
        return true;
      }).toList();

      // Mantenemos solo los últimos mensajes según el límite
      final finalHistory = uniqueHistory.length > maxChatHistoryLength
          ? uniqueHistory.sublist(uniqueHistory.length - maxChatHistoryLength)
          : uniqueHistory;

      camilaChatHistory.value = List.from(finalHistory);
      notifyListeners();
    }
  }

  // --- ACTUALIZADO EN MODEL ---
  Future<void> clearChatHistoryUI() async {
    // 1. Clonamos la plática actual para mandarla a compresión en background
    final historySnapshot = List<Map<String, dynamic>>.from(camilaChatHistory.value);

    // 2. ¡Vaciamos la lista en memoria y notificamos a la UI INMEDIATAMENTE!
    camilaChatHistory.value = [];
    notifyListeners();

    // 3. Sobrescribimos la memoria persistente
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('camilaChatHistory');

    debugPrint("🧹 Historial visual borrado al instante.");

    // 4. Ejecutamos la compresión de forma asíncrona sin bloquear la UI
    // Usamos Future.microtask para que corra independientemente en el background
    Future.microtask(() => compressEpisodicMemory(historySnapshot));
  }

  // --- NUEVA FUNCIÓN EN MODEL ---
  Future<void> compressEpisodicMemory([List<Map<String, dynamic>>? overrideHistory]) async {
    final targetHistory = overrideHistory ?? camilaChatHistory.value;
    if (targetHistory.isEmpty) return;

    debugPrint("🧠 Iniciando compresión de memoria episódica...");

    String rawHistoryText = '';
    for (var msg in targetHistory) {
      final role = msg['role'] ?? 'unknown';
      final content = msg['content'];

      String textContent = '';
      bool hasImage = false;

      if (content is String) {
        textContent = content;
      } else if (content is List) {
        for (var item in content) {
          if (item is Map) {
            if (item['type'] == 'text' && item.containsKey('text')) {
              textContent += '${item['text']} ';
            } else if (item['type'] == 'image_url') {
              hasImage = true;
            }
          }
        }
      }

      if (msg.containsKey('hidden_transcript') &&
          msg['hidden_transcript'].toString().trim().isNotEmpty) {
        textContent = msg['hidden_transcript'];
      }

      if (hasImage && textContent.trim().isEmpty) {
        textContent = "[El usuario envió una imagen]";
      } else if (hasImage && textContent.trim().isNotEmpty) {
        textContent += " [Imagen adjunta]";
      }

      if (textContent.trim().isNotEmpty) {
        rawHistoryText += "[$role]: ${textContent.trim()}\n";
      }
    }

    if (rawHistoryText.trim().isNotEmpty) {
      final recentMemory = objectbox.getMostRecentEpisodicMemory();
      final now = DateTime.now();

      bool isToday = false;
      String? existingSummary;

      if (recentMemory != null) {
        final memDate = recentMemory.createdAt;
        if (memDate.year == now.year &&
            memDate.month == now.month &&
            memDate.day == now.day) {
          isToday = true;
          existingSummary = recentMemory.summary;
        }
      }

      final instructions = PromptManager.getEpisodicSummaryInstructions(
          existingSummary: existingSummary);

      final responsesService = OpenAiResponsesService();
      // ¡AQUÍ ESTÁ LA MAGIA! Sintetizamos lo que está en la pantalla
      final newSummary = await responsesService.generateSummary(
          instructions, rawHistoryText.trim());

      if (newSummary != null && newSummary.isNotEmpty) {
        if (isToday && recentMemory != null) {
          recentMemory.summary = newSummary;
          recentMemory.createdAt = now;
          objectbox.upsertEpisodicMemory(recentMemory);
        } else {
          final newMemory = EpisodicMemory(summary: newSummary, createdAt: now);
          objectbox.upsertEpisodicMemory(newMemory);
        }
        debugPrint("🧠 Memoria episódica comprimida y guardada exitosamente.");
      }
    }
  }

  Future<void> playRandomDefaultAudio() async {
    // Lista de audios por defecto
    final defaultAudios = [
      'defaultAudio1.mp3',
      'defaultAudio2.mp3',
      'defaultAudio3.mp3',
    ];

    // Seleccionar un audio al azar
    final randomIndex = Random().nextInt(defaultAudios.length);
    final randomAudio = defaultAudios[randomIndex];

    // Reproducir el audio seleccionado
    await audioPlayer.play(AssetSource(randomAudio));
  }

  // [chatHistory] is a map containing the chat history.
  Future<String> sendUserInput(BuildContext context) async {
    try {
      final chatHistory = camilaChatHistory.value;
      final response =
          await openAIService.getResponseFromTextInput(context, chatHistory);
      return response;
    } catch (e) {
      await playRandomDefaultAudio();
      return 'Error sending request.';
    }
  }

  Future<String> sendUserAudioInput(
      BuildContext context, String filePath) async {
    try {
      // Leer el archivo de audio y convertirlo a Uint8List
      final audioFile = File(filePath);
      final audioBytes = await audioFile.readAsBytes();

      // Obtener el historial del chat
      final chatHistory = camilaChatHistory.value;

      // Llamar a la función de la API con los datos del audio
      final response = await openAIService.getResponseFromAudioInput(
        context,
        chatHistory,
        audioBytes,
        'wav', // Especificar el formato del archivo de audio
      );

      return response;
    } catch (e) {
      await playRandomDefaultAudio();
      return 'Error sending request.';
    }
  }

  // Future<String?> getAudioFromText(String response) async {
  //   try {
  //     final speech = response;
  //     final audioPath = await openAIService.generateSpeech(speech);
  //     return audioPath;
  //   } catch (e) {
  //     debugPrint('Excepción atrapada: $e');
  //     return null;
  //   }
  // }

  Future<String?> getImage({required ImageSource source}) async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (pickedFile != null) {
        final imageBytes = await pickedFile.readAsBytes();
        final base64String = base64Encode(imageBytes);

        // Detectar automáticamente el formato basado en la extensión del archivo
        String mimeType = 'image/jpeg';
        if (pickedFile.path.toLowerCase().endsWith('.png')) {
          mimeType = 'image/png';
        } else if (pickedFile.path.toLowerCase().endsWith('.webp')) {
          mimeType = 'image/webp';
        }

        // Devolvemos el string YA ARMADO con su prefijo correcto
        return 'data:$mimeType;base64,$base64String';
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
    return null;
  }

  Future<String?> getThumbnailBase64(String imageBase64) async {
    try {
      // 1. Limpiamos el prefijo para obtener solo la data pura
      final String cleanBase64 =
          imageBase64.contains(',') ? imageBase64.split(',').last : imageBase64;

      // 2. Decodificamos de forma segura
      final decodedBytes = base64Decode(cleanBase64);
      final image = img.decodeImage(decodedBytes);

      if (image == null) return null;

      // Obtener las dimensiones originales de la imagen
      final originalWidth = image.width;
      final originalHeight = image.height;

      // Definir el ancho deseado para la miniatura
      const thumbnailWidth = 100;

      // Calcular el alto manteniendo la proporción
      final thumbnailHeight = (originalHeight * thumbnailWidth) / originalWidth;

      // Redimensionar la imagen manteniendo la proporción
      final thumbnail = img.copyResize(image,
          width: thumbnailWidth, height: thumbnailHeight.toInt());

      // Nota: Retornamos la miniatura como Base64 puro porque esto solo
      // lo usará tu UI (Image.memory) localmente, no se enviará a OpenAI.
      return base64Encode(img.encodeJpg(thumbnail));
    } catch (e) {
      debugPrint('Error generando miniatura: $e');
      return null;
    }
  }

  Map<String, dynamic> convertToGPTFormat(String message, String role,
      {String? username, String? imageBase64}) {
    if (imageBase64 != null) {
      return {
        'role': role,
        'content': [
          {
            "type": "text",
            "text": message,
          },
          {
            'type': 'image_url',
            'image_url': {
              'url': imageBase64, // Ya viene perfecto desde getImage
              'detail': 'low'
            }
          },
        ],
        if (username != null) 'name': username,
      };
    } else {
      return {
        'role': role,
        'content': message,
        if (username != null)
          'name': username, // Añadir 'name' si 'username' no es null
      };
    }
  }

  void updateChatHistory(List<Map<String, dynamic>> newChatHistory) {
    camilaChatHistory.value = newChatHistory;
    notifyListeners(); // Notifies listeners that the value has changed
  }

  void addUserMessage(String userName, message,
      {String? imageBase64, String? thumbnailBase64}) {
    if (isWipingMemory) return; // 🔒 QUARANTINE LOCK

    String cleanedUserName = userName.replaceAll(RegExp(r'\s.*'), '');

    final newUserMessage = convertToGPTFormat(message, 'user',
        username: cleanedUserName, imageBase64: imageBase64);

    // LA MAGIA: Guardamos la miniatura DENTRO del mismo mensaje
    if (thumbnailBase64 != null) {
      newUserMessage['local_thumbnail'] = thumbnailBase64;
    }

    // 🚀 MEJORA DE REACTIVIDAD: Creamos la nueva lista, la manipulamos y asignamos al final.
    final updatedChatHistory =
        List<Map<String, dynamic>>.from(camilaChatHistory.value)
          ..add(newUserMessage);

    // Truncamos ANTES de asignar para que la notificación lleve el estado final.
    if (updatedChatHistory.length > maxChatHistoryLength) {
      updatedChatHistory.removeRange(0, updatedChatHistory.length - maxChatHistoryLength);
    }

    updateChatHistory(updatedChatHistory);
  }

  void addModelMessage(String message) {
    if (isWipingMemory) return; // 🔒 QUARANTINE LOCK

    final newModelMessage = convertToGPTFormat(message, 'assistant');
    final updatedChatHistory =
        List<Map<String, dynamic>>.from(camilaChatHistory.value)
          ..add(newModelMessage);
    
    // Truncamos por si acaso
    if (updatedChatHistory.length > maxChatHistoryLength) {
      updatedChatHistory.removeRange(0, updatedChatHistory.length - maxChatHistoryLength);
    }

    updateChatHistory(updatedChatHistory);
  }

  void updateLastUserHiddenTranscript(String transcript) {
    if (isWipingMemory) return; // 🔒 QUARANTINE LOCK
    if (camilaChatHistory.value.isEmpty) return;

    // 🛡️ FILTRO ANTI-ALUCINACIONES DE WHISPER
    // Si la transcripción contiene caracteres asiáticos, cirílicos o frases clásicas de alucinación, la ignoramos.
    final lowerTranscript = transcript.toLowerCase().trim();
    final RegExp asianCharacters =
        RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]');
    if (asianCharacters.hasMatch(transcript) ||
        lowerTranscript.contains("subtitles by") ||
        lowerTranscript == "thank you." ||
        lowerTranscript == "thank you" ||
        lowerTranscript == "thanks.") {
      debugPrint(
          "🛡️ Alucinación de Whisper detectada y bloqueada: $transcript");
      return;
    }

    // Buscamos el último mensaje del usuario de atrás hacia adelante
    for (int i = camilaChatHistory.value.length - 1; i >= 0; i--) {
      if (camilaChatHistory.value[i]['role'] == 'user') {
        final updatedMessage =
            Map<String, dynamic>.from(camilaChatHistory.value[i]);
        updatedMessage['hidden_transcript'] = transcript;

        final updatedChatHistory =
            List<Map<String, dynamic>>.from(camilaChatHistory.value);
        updatedChatHistory[i] = updatedMessage;

        updateChatHistory(updatedChatHistory);
        break;
      }
    }
  }

  // 🧠 EXTRAE LOS ÚLTIMOS MENSAJES PARA LA RECONEXIÓN
  String getRecentContextForReconnection({int limit = 5}) {
    final history = camilaChatHistory.value;
    if (history.isEmpty) return "";

    // Solo tomamos los últimos 'limit' mensajes para no saturar el token limit
    int start = history.length > limit ? history.length - limit : 0;
    String contextStr = "";

    for (int i = start; i < history.length; i++) {
      final msg = history[i];
      final role = msg['role'] ?? 'unknown';
      final content = msg['content'];

      String textContent = '';
      bool hasImage = false;

      if (content is String) {
        textContent = content;
      } else if (content is List) {
        for (var item in content) {
          if (item is Map) {
            if (item['type'] == 'text' && item.containsKey('text')) {
              textContent += '${item['text']} ';
            } else if (item['type'] == 'image_url') {
              hasImage = true;
            }
          }
        }
      }

      // Leemos el doble fondo de audio
      if (msg.containsKey('hidden_transcript') &&
          msg['hidden_transcript'].toString().trim().isNotEmpty) {
        textContent = msg['hidden_transcript'];
      }

      // Validamos si fue una foto sola
      if (hasImage && textContent.trim().isEmpty) {
        textContent = "[Imagen adjunta]";
      } else if (hasImage && textContent.trim().isNotEmpty) {
        textContent += " [Imagen adjunta]";
      }

      if (textContent.trim().isNotEmpty) {
        contextStr += "[$role]: ${textContent.trim()}\n";
      }
    }
    return contextStr.trim();
  }

  @override
  void dispose() {
    listViewController.dispose();
    textFieldFocusNode.dispose();
    secondaryTextFieldFocusNode.dispose();
    textController.dispose();
    super.dispose();
  }
}
