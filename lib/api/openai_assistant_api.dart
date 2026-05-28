// @file openai_assistant_api.dart
// @brief High-level integration bridging the OpenAI Assistants v2 API for heavy-duty RAG flows.
// @author Lorenzo Martínez
// @date 2026-03-30
// @version 1.0.0

import 'dart:async';
import 'dart:convert';
//import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// @brief Manager class routing complex multi-threading session IDs specifically to Santiago or data bots.
class Assistants {
  final String apiKey;
  final String santiagoId;
  //final HttpClient _client;
  final Map<String, String> threads;

  Assistants({required this.apiKey, required this.santiagoId})
      : threads = {'Lorenzo': 'thread_p8Pcahw4L9aBplRiHk2Htcat'};

  /// @brief Core orchestrator matching local user IDs to external thread mappings prior to querying the RAG.
  /// @param user Target namespace identifying the conversation root.
  /// @param message Live string input feeding the query.
  /// @return `Future<String>`
  Future<String> assistantManager(String user, String message) async {
    debugPrint("Dentro de la clase en AssistantManager");
    final assistantId = santiagoId;
    debugPrint("El ID del asistente es: $assistantId");
    try {
      final myAssistant = await retrieveAssistant(assistantId);

      // Revisar si el usuario ya tiene un thread
      String? threadId = threads[user];
      if (threadId != null) {
        debugPrint("Thread encontrado para el usuario: $user");
        // Agregar mensaje al hilo existente
        await createMessage(threadId, message);
      } else {
        debugPrint("Creando un nuevo thread para el usuario: $user");
        // Crear un nuevo thread para el usuario
        final newThread = await createThread(message);
        threadId = newThread['id']; // Asignar el ID del nuevo thread
        threads[user] = threadId!; // Asociar el thread con el usuario
      }

      // Ejecutar el asistente en el thread del usuario
      await runAssistant(threadId, myAssistant['id']);

      // Obtener la respuesta desde los mensajes
      final response = await listMessages(threadId);
      debugPrint(
          "El mensaje de la lista es: ${response['data'][0]['content'][0]['text']['value']}");
      return response['data'][0]['content'][0]['text']['value'];
    } catch (e) {
      debugPrint('Error while processing input: $e');
      return "Lo siento, por el momento no tengo acceso a la base de datos y a la informacion que requieres, intentalo mas tarde.";
    }
  }

  /// @brief Connects directly to the OpenAI endpoints to validate the active state of an Assistant.
  /// @param assistantId Target namespace referencing the specific OpenAI avatar.
  /// @return `Future<Map<String, dynamic>>`
  Future<Map<String, dynamic>> retrieveAssistant(String assistantId) async {
    debugPrint("En retrieve assistant");
    final url = Uri.parse('https://api.openai.com/v1/assistants/$assistantId');

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'assistants=v2',
        },
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        return json.decode(responseBody);
      } else {
        debugPrint("La descripcion es: ${response.headers}");
        throw Exception(
            'Failed to retrieve assistant. Status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error retrieving assistant: $e');
      return {}; // Devuelve un mapa vacío en caso de error
    }
  }

  /// @brief Generates an isolated session thread keeping the conversation isolated from other app sessions.
  /// @param context The baseline initial injection string.
  /// @return `Future<Map<String, dynamic>>`
  Future<Map<String, dynamic>> createThread(String context) async {
    debugPrint("En create thread");
    const url = 'https://api.openai.com/v1/threads';
    final requestPayload = json.encode({
      'messages': [
        {
          'role': 'user',
          'content': context,
        },
      ],
    });

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'assistants=v2',
        },
        body: requestPayload,
      );

      if (response.statusCode == 201) {
        debugPrint("Exito");
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to create thread. Status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error creating thread: $e');
      return {}; // Devuelve un mapa vacío en caso de error
    }
  }

  /// @brief Pushes a solitary message node into the active OpenAI Thread sequence queue.
  /// @param threadId Active active thread UUID.
  /// @param content User instruction string payload.
  /// @return `Future<Map<String, dynamic>>`
  Future<Map<String, dynamic>> createMessage(
      String threadId, String content) async {
    debugPrint("En createMessage");
    final url = 'https://api.openai.com/v1/threads/$threadId/messages';

    // Payload con el formato correcto
    final requestPayload = json.encode({
      'role': 'user',
      'content': [
        {
          'type': 'text',
          'text': content, // Aseguramos que 'text' sea un string
        },
      ],
    });

    try {
      // Realizar la solicitud POST usando el paquete 'http'
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'assistants=v2',
        },
        body: requestPayload,
      );

      // Comprobar el código de respuesta
      if (response.statusCode == 200) {
        // Usar utf8.decode para manejar caracteres especiales
        final decodedBody = utf8.decode(response.bodyBytes);
        final responseBody = json.decode(decodedBody);
        debugPrint("Mensaje creado exitosamente: $responseBody");
        return responseBody;
      } else {
        throw Exception(
            'Failed to create message. Status code: ${response.statusCode}, body: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error creating message: $e');
      return {}; // Retorna un mapa vacío en caso de error
    }
  }

  /// @brief Executes a dedicated Run processing cycle over a filled thread causing the assistant to spin up compute.
  /// @param userThreadId Target thread UUID.
  /// @param assistantId Processing Assistant UUID.
  /// @return `Future<void>`
  Future<void> runAssistant(String userThreadId, String assistantId) async {
    final url = 'https://api.openai.com/v1/threads/$userThreadId/runs';
    final requestPayload = json.encode({
      'assistant_id': assistantId,
    });
    debugPrint("El thread ID es: $userThreadId");

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'assistants=v2',
        },
        body: requestPayload,
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to run assistant. Status code: ${response.statusCode}');
      }

      final runId = json.decode(response.body)['id'];
      final completer = Completer<void>();

      // Método para verificar el estado de la ejecución periódicamente
      Future<void> checkRunStatus() async {
        while (!completer.isCompleted) {
          try {
            final runStatusResponse = await http.get(
              Uri.parse('$url/$runId'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
                'OpenAI-Beta': 'assistants=v2',
              },
            );

            if (runStatusResponse.statusCode == 200) {
              final runStatus = json.decode(runStatusResponse.body);
              if (runStatus['status'] == 'completed') {
                completer.complete();
                break;
              }
            } else {
              completer.completeError(
                  'Failed to check run status. Status code: ${runStatusResponse.statusCode}');
            }

            // Esperar antes de verificar nuevamente
            await Future.delayed(const Duration(seconds: 5));
          } catch (e) {
            completer.completeError('Error checking run status: $e');
          }
        }
      }

      await checkRunStatus();

      return completer.future;
    } catch (e) {
      debugPrint('Error running assistant: $e');
    }
  }

  /// @brief Extracts the fully processed response array once a Run cycle resolves to `completed`.
  /// @param threadId Target thread UUID.
  /// @return `Future<Map<String, dynamic>>`
  Future<Map<String, dynamic>> listMessages(String threadId) async {
    final url = 'https://api.openai.com/v1/threads/$threadId/messages';
    debugPrint("En list messages");

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'assistants=v2',
        },
      );

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        return json.decode(responseBody);
      } else {
        throw Exception(
            'Failed to list messages. Status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error listing messages: $e');
      return {}; // Devuelve un mapa vacío en caso de error
    }
  }
}
