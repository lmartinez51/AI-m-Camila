// @file openai_responses_service.dart
// @brief Handles ultra-concise conversation summaries acting directly over the OpenAI Responses API.
// @author Lorenzo Martínez
// @date 2026-03-30
// @version 1.0.0

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// @brief Service designed to strictly generate prompt-driven context summaries suppressing heavy reasoning.
class OpenAiResponsesService {
  final String apiKey = dotenv.env['OPENAI_API_NEW_KEY'] ?? '';
  final String responsesApiUrl = 'https://api.openai.com/v1/responses';

  /// @brief Submits deep chat history into a highly constrained prompt context to output a fast minimal summary string.
  /// @param instructions The system instruction tuning the summary tone.
  /// @param chatHistory The raw conversation backlog passed dynamically.
  /// @return `Future<String?>` The processed string representing the minimal footprint summary.
  Future<String?> generateSummary(
      String instructions, String chatHistory) async {
    try {
      final requestBody = jsonEncode({
        'model': 'gpt-5-nano-2025-08-07',
        'instructions': instructions,
        'input': chatHistory,
        'store': false,
        // 🧠 Apagamos el motor de razonamiento profundo
        'reasoning': {'effort': 'minimal', 'summary': null},

        // 🗣️ Forzamos respuestas ultra concisas y directas
        "text": {
          "format": {"type": "text"},
          "verbosity": "low"
        },

        // 🛡️ Nuestro salvavidas: Le damos espacio suficiente para el texto final
        // (150-400 es lo ideal para no asfixiarlo aunque ya no esté "pensando" tanto)
        'max_output_tokens': 600,
      });

      final response = await http.post(
        Uri.parse(responsesApiUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        debugPrint('🤖 [DEBUG] RESPUESTA CRUDA DE OPENAI: ${response.body}');
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        String summary = '';

        // Navegamos por la nueva estructura de Responses API
        if (data['output'] != null && data['output'] is List) {
          for (var item in data['output']) {
            // Buscamos el bloque que sea el mensaje real, ignorando el de razonamiento
            if (item['type'] == 'message' &&
                item['content'] != null &&
                item['content'] is List) {
              for (var contentItem in item['content']) {
                // Extraemos el texto
                if (contentItem['type'] == 'output_text' &&
                    contentItem['text'] != null) {
                  summary = contentItem['text'];
                  break;
                }
              }
            }
          }
        }

        // Fallback por si en el futuro cambian a la estructura vieja de completions
        if (summary.isEmpty &&
            data['choices'] != null &&
            data['choices'].isNotEmpty) {
          summary = data['choices'][0]['message']['content'] ?? '';
        }

        debugPrint('📝 Resumen generado: $summary');
        return summary.trim();
      } else {
        debugPrint(
            'Error generating summary: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception in OpenAiResponsesService.generateSummary: $e');
      return null;
    }
  }
}
