// @file gemini_tool_handler.dart
// @brief Mixin implementing Gemini Live function-call execution routing.
// @author Lorenzo Martínez
// @date 2026-04-05
// @version 1.0.0
//
// ARCHITECTURE NOTE:
// This is a free-standing mixin (no `on` constraint) that declares abstract
// bridges for the three UI callbacks and sendEvent(), which the host class
// (GeminiWebSocketService) fulfills automatically via its own field declarations
// and its concrete sendEvent() implementation.
//
// This design avoids the Dart circular-superinterface problem that arises when
// using `mixin on GeminiWebSocketService` (self-reference) or
// `mixin on AIVoiceService` with a `with ... implements ...` class declaration.

import 'package:aimcamila/database/objectbox_service.dart';
import 'package:aimcamila/models/semantic_memory.dart';
import 'package:aimcamila/objectbox.g.dart';
import 'package:flutter/foundation.dart';

/// @brief Mixin providing Gemini-specific tool execution routing.
///
/// Applied via `class GeminiWebSocketService with GeminiToolHandler implements AIVoiceService`.
/// The mixin's abstract members are satisfied by GeminiWebSocketService's own
/// concrete implementations.
mixin GeminiToolHandler {
  // ---------------------------------------------------------------------------
  // Abstract bridges — satisfied by the host class (GeminiWebSocketService)
  // ---------------------------------------------------------------------------

  /// @brief Sends a JSON-encoded event down the active Gemini WebSocket channel.
  void sendEvent(Map<String, dynamic> event);

  /// @brief Fires when the AI triggers `execute_app_command`.
  Function(String command)? get onAppCommandTriggered;

  /// @brief Fires when the AI triggers `end_conversation`.
  Function()? get onEndConversationTriggered;

  // ---------------------------------------------------------------------------
  // 🟢 EL INTERCEPTOR DE HERRAMIENTAS (Gemini Live)
  // ---------------------------------------------------------------------------

  /// @brief Intercepts tool calls issued by Gemini, executes local logic, and
  /// returns a `toolResponse` to satisfy Gemini's function-call contract.
  ///
  /// @param functionCall Dictionary containing `name`, `args`, and `id` fields
  ///   as defined by the Gemini BidiGenerateContent protocol.
  void handleGeminiFunctionCall(Map<String, dynamic> functionCall) async {
    try {
      final String functionName = functionCall['name'];
      final Map<String, dynamic> arguments = functionCall['args'] ?? {};
      final String callId = functionCall['id']; // Gemini usa 'id', no 'call_id'

      debugPrint("🛠️ [GEMINI RAG]: Camila quiere ejecutar: $functionName");

      String answerMessage = "";

      // --- 1. SANTIAGO (Web Search) ---
      // [DEPRECATED FOR GEMINI]: Now using native Search Grounding {"googleSearch":{}}
      // The model uses 'googleSearch' tool directly, we don't handle it here anymore.

      // --- 2. MEMORIA (Guardar) ---
      if (functionName == 'save_user_memory') {
        final category = arguments['category'];
        final content = arguments['content'];
        final box = objectbox.store.box<SemanticMemory>();
        final query =
            box.query(SemanticMemory_.category.equals(category)).build();
        final existingMemory = query.findFirst();
        query.close();

        if (existingMemory != null) {
          existingMemory.content = content;
          existingMemory.updatedAt = DateTime.now();
          box.put(existingMemory);
        } else {
          box.put(SemanticMemory(category: category, content: content));
        }
        answerMessage =
            "System Success: Saved '$content' under category '$category'.";
      }

      // --- 3. MEMORIA (Buscar) ---
      else if (functionName == 'search_user_memory') {
        final query = arguments['query']?.toString().toLowerCase() ?? '';
        final box = objectbox.store.box<SemanticMemory>();
        final allMemories = box.getAll();

        List<String> foundMemories = [];
        for (var memory in allMemories) {
          final searchString =
              "${memory.category} ${memory.content}".toLowerCase();
          if (searchString.contains(query) ||
              query.split(' ').any(
                  (word) => word.length > 3 && searchString.contains(word))) {
            foundMemories.add("${memory.category}: ${memory.content}");
          }
        }
        answerMessage = foundMemories.isNotEmpty
            ? "Results found: ${foundMemories.join(' | ')}. Use this info to answer the user naturally."
            : "No records found regarding '$query'.";
      }

      // --- 4. AGENDA ---
      else if (functionName == 'manage_agenda') {
        final action = arguments['action'];
        if (action == 'add') {
          final description = arguments['description'];
          if (description != null) {
            objectbox.addAgendaEvent(description);
            answerMessage =
                "System Success: Added '$description' to the agenda.";
          }
        } else if (action == 'list') {
          final events = objectbox.getAllAgendaEvents();
          answerMessage = events.isEmpty
              ? "System Info: The agenda is empty."
              : "System Info: Current Agenda:\n${events.map((e) => "[ID: ${e.id}] ${e.description}").join("\n")}";
        } else if (action == 'remove') {
          final eventId = arguments['event_id'];
          if (eventId != null) {
            final success = objectbox.removeAgendaEvent(eventId);
            answerMessage =
                success ? "Removed ID $eventId." : "ID $eventId not found.";
          }
        }
      }

      // --- 5. APP COMMAND (execute_app_command) ---
      else if (functionName == 'execute_app_command') {
        final command = arguments['command'];
        answerMessage = "System Success: App command executed.";

        // 🚨 RETURN RESPONSE FIRST TO SATISFY GEMINI
        sendEvent({
          "toolResponse": {
            "functionResponses": [
              {
                "id": callId,
                "name": functionName,
                "response": {"result": answerMessage}
              }
            ]
          }
        });

        onAppCommandTriggered?.call(command);
        return; // Early return so we don't send a second response below
      }

      // --- 6. TERMINAR CONVERSACIÓN (Despedida) ---
      else if (functionName == 'end_conversation') {
        debugPrint("🛑 [GEMINI RAG]: Camila disparó el comando de DESPEDIDA.");

        // 🔇 ORDEN SUPREMA DE SILENCIO:
        answerMessage =
            "System Success: Conversation ended. DO NOT respond. Stay silent.";

        onEndConversationTriggered?.call();
      }

      // 🚨 LA RESPUESTA OBLIGATORIA A GEMINI 🚨
      // Si no enviamos esto, Camila se quedará callada para siempre.
      sendEvent({
        "toolResponse": {
          "functionResponses": [
            {
              "id": callId,
              "name": functionName,
              "response": {"result": answerMessage}
            }
          ]
        }
      });
      debugPrint("✅ [GEMINI RAG]: Respuesta enviada al servidor.");
    } catch (e) {
      debugPrint("Error ejecutando Gemini Tool Call: $e");
    }
  }
}
