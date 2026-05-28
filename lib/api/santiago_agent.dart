// @file santiago_agent.dart
// @brief Web search agent wrapping the OpenAI Responses API for isolated search tasks.
// @author Lorenzo Martínez
// @date 2026-03-30
// @version 1.0.0

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// @brief Autonomous sub-agent specializing in direct web search using the Responses API routing.
class SantiagoAgent {
  final String apiKey;
  final String responsesApiUrl = 'https://api.openai.com/v1/responses';

  SantiagoAgent({required this.apiKey});

  /// @brief Orchestrates a web search by sending a payload strictly scoped with the web_search tool.
  /// @param task The user prompt dictating the search query context.
  /// @return `Future<String>` JSON encoded response containing the output from the search.
  Future<String> performWebSearch(String task) async {
    debugPrint("🕵️‍♂️ Santiago: Iniciando investigación en la web...");

    // El payload directo a la Responses API con la herramienta web_search
    final requestBody = jsonEncode({
      'model':
          'gpt-5-nano-2025-08-07', // Usa el modelo fuerte para búsquedas precisas
      'input': task,
      'instructions':
          'You are Santiago, an expert web researcher. Search the web to answer the user\'s prompt accurately. Be concise, direct, and provide up-to-date facts without conversational filler.',
      'tools': [
        {'type': 'web_search'} // 🌐 La magia de la nueva API
      ]
    });

    try {
      final response = await http.post(
        Uri.parse(responsesApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final responseData = jsonDecode(decodedBody);

        // Buscamos el texto final en la respuesta de la API
        final outputItems = responseData['output'] as List;
        String finalAnswer = "No encontré una respuesta clara en la web.";

        for (var item in outputItems) {
          if (item['type'] == 'message' && item['content'] != null) {
            finalAnswer = item['content'][0]['text'];
          }
        }

        debugPrint("🕵️‍♂️ Santiago: Búsqueda completada -> $finalAnswer");
        // Devolvemos el mismo formato JSON que tu código ya esperaba
        return jsonEncode({'assistant_response': finalAnswer});
      } else {
        debugPrint(
            "Error de Santiago: ${response.statusCode} - ${response.body}");
        return jsonEncode({
          'assistant_response':
              "Lo siento, tuve un problema conectándome a internet. Error ${response.statusCode}."
        });
      }
    } catch (e) {
      debugPrint('Error en SantiagoAgent: $e');
      return jsonEncode(
          {'assistant_response': "Lo siento, mi conexión a internet falló."});
    }
  }
}
