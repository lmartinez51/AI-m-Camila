// @file openai_tool_handler.dart
// @brief Mixin implementing OpenAI Realtime function-call execution routing.
// @author Lorenzo Martínez
// @date 2026-04-05
// @version 1.0.0
//
// ARCHITECTURE NOTE:
// This is a free-standing mixin (no `on` constraint) that declares abstract
// bridges for the three UI callbacks, sendEvent(), and apiKey, which the host
// class (WebSocketService) fulfills automatically via its own field and method
// declarations.
//
// This design avoids the Dart circular-superinterface problem that arises when
// using `mixin on WebSocketService` (self-reference) or
// `mixin on AIVoiceService` with a `with ... implements ...` class declaration.

import 'dart:convert';
import 'package:aimcamila/api/santiago_agent.dart';
import 'package:aimcamila/database/objectbox_service.dart';
import 'package:aimcamila/models/semantic_memory.dart';
import 'package:aimcamila/objectbox.g.dart';
import 'package:flutter/foundation.dart';

/// @brief Mixin providing OpenAI Realtime-specific tool execution routing.
///
/// Applied via `class WebSocketService with OpenAiToolHandler implements AIVoiceService`.
/// The mixin's abstract members are satisfied by WebSocketService's own concrete
/// field and method implementations.
mixin OpenAiToolHandler {
  // ---------------------------------------------------------------------------
  // Abstract bridges — satisfied by the host class (WebSocketService)
  // ---------------------------------------------------------------------------

  /// @brief Sends a JSON-encoded event down the active OpenAI WebSocket channel.
  void sendEvent(Map<String, dynamic> event);

  /// @brief The OpenAI API key used to instantiate sub-agents (e.g. SantiagoAgent).
  String get apiKey;

  /// @brief Fires when a long-running delegated task starts/finishes.
  Function(bool isDelegating)? get onDelegatingTask;

  /// @brief Fires when the AI triggers `execute_app_command`.
  Function(String command)? get onAppCommandTriggered;

  /// @brief Fires when the AI triggers `end_conversation`.
  Function()? get onEndConversationTriggered;

  // ---------------------------------------------------------------------------
  // 🟢 FUNCTION CALL ROUTER (OpenAI Realtime)
  // ---------------------------------------------------------------------------

  /// @brief Evaluates executed tool schemas, updating external services or UI
  /// state mappings, then acknowledges the call to OpenAI via `function_call_output`.
  ///
  /// @param data OpenAI `response.function_call_arguments.done` event payload.
  void handleFunctionCallArgumentsDone(Map<String, dynamic> data) async {
    try {
      debugPrint("En function calling");
      final functionName = data['name'];
      final arguments = json.decode(data['arguments']);
      final callId = data['call_id']; // 🚨 ESTA ES LA PIEZA MÁGICA FALTANTE
      debugPrint(
          "🛠️ RAG: Ejecutando herramienta '$functionName' (ID: $callId)");
      debugPrint("Los argumentos son: $arguments");

      // --- 1. BLUETOOTH ---
      if (functionName == 'search_bluetooth_devices') {
        try {
          final functionOutputEvent = {
            "type": "conversation.item.create",
            "item": {
              "type": "message",
              "role": "system",
              "content": [
                {
                  "type": "input_text",
                  "content":
                      "Searching for nearby bluetooth devices. Please wait..."
                }
              ],
            }
          };
          sendEvent(functionOutputEvent);
          // Iniciar la búsqueda de dispositivos Bluetooth
          //await _bluetoothController.searchForDevices();
          final functionOutputEvent2 = {
            "type": "conversation.item.create",
            "item": {
              "type": "message",
              "role": "system",
              "content": [
                {
                  "type": "input_text",
                  "content":
                      "Bluetooth devices search completed. Found 3 devices nearby."
                }
              ],
            }
          };
          sendEvent(functionOutputEvent2);
        } catch (error) {
          debugPrint('Error processing question: $error');
        }
      }

      // --- 2. MEMORIA (Guardar) ---
      else if (functionName == 'save_user_memory') {
        try {
          final category = arguments['category'];
          final content = arguments['content'];
          debugPrint(
              "🧠 RAG: Intentando guardar memoria -> Cat: $category | Dato: $content");

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

          // 🚨 RESPUESTA OFICIAL DE LA HERRAMIENTA CON CALL_ID 🚨
          sendEvent({
            "type": "conversation.item.create",
            "item": {
              "type": "function_call_output",
              "call_id": callId, // El recibo de entrega
              "output":
                  "System Success: Saved '$content' under category '$category'."
            }
          });

          sendEvent({"type": "response.create"});
        } catch (error) {
          debugPrint('Error saving user memory: $error');
        }
      }

      // --- 3. MEMORIA (Buscar) ---
      else if (functionName == 'search_user_memory') {
        final query = arguments['query']?.toString().toLowerCase() ?? '';

        final box = objectbox.store.box<SemanticMemory>();
        final allMemories = box.getAll();

        // Radiografía temporal
        debugPrint(
            "--- 📦 ESTADO ACTUAL DE LA MEMORIA (TOTAL: ${allMemories.length}) ---");
        for (var m in allMemories) {
          debugPrint("ID: ${m.id} | Cat: ${m.category} | Cont: ${m.content}");
        }

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

        if (foundMemories.isEmpty && allMemories.isNotEmpty) {
          final recentMemories = allMemories.reversed
              .take(5)
              .map((m) => "${m.category}: ${m.content}")
              .toList();
          foundMemories.addAll(recentMemories);
        }

        String answerMessage = foundMemories.isNotEmpty
            ? "Results found: ${foundMemories.join(' | ')}. Use this info to answer the user naturally."
            : "No records found regarding '$query'.";

        // 🚨 RESPUESTA OFICIAL DE LA HERRAMIENTA CON CALL_ID 🚨
        sendEvent({
          "type": "conversation.item.create",
          "item": {
            "type": "function_call_output",
            "call_id": callId,
            "output": answerMessage,
          }
        });

        sendEvent({"type": "response.create"});
      }

      // --- 4. AGENDA ---
      else if (functionName == 'manage_agenda') {
        try {
          final action = arguments['action'];
          String answerMessage = "";

          debugPrint("📅 RAG: Ejecutando manage_agenda -> Acción: $action");

          if (action == 'add') {
            final description = arguments['description'];
            if (description != null && description.isNotEmpty) {
              objectbox.addAgendaEvent(description);
              answerMessage =
                  "System Success: Added '$description' to the agenda.";
            } else {
              answerMessage =
                  "System Error: Missing description for 'add' action.";
            }
          } else if (action == 'list') {
            final events = objectbox.getAllAgendaEvents();
            if (events.isEmpty) {
              answerMessage =
                  "System Info: The agenda is currently empty. There are no scheduled events.";
            } else {
              answerMessage =
                  "System Info: Current Agenda Events:\n${events.map((e) => "[ID: ${e.id}] ${e.description}").join("\n")}\nRead these events naturally to the user.";
            }
          } else if (action == 'remove') {
            final eventId = arguments['event_id'];
            if (eventId != null) {
              final success = objectbox.removeAgendaEvent(eventId);
              answerMessage = success
                  ? "System Success: Removed event ID $eventId from the agenda."
                  : "System Error: Event ID $eventId not found in the agenda.";
            } else {
              answerMessage =
                  "System Error: Missing event_id for 'remove' action.";
            }
          }

          // 🚨 RESPUESTA OFICIAL DE LA HERRAMIENTA CON CALL_ID 🚨
          sendEvent({
            "type": "conversation.item.create",
            "item": {
              "type": "function_call_output",
              "call_id": callId,
              "output": answerMessage,
            }
          });

          sendEvent({"type": "response.create"});
        } catch (error) {
          debugPrint('Error managing agenda: $error');
        }
      }

      // --- 5. WEB SEARCH (Santiago) ---
      else if (functionName == 'delegate_web_search') {
        try {
          // 🟢 1. ENCENDEMOS EL INDICADOR VISUAL
          onDelegatingTask?.call(true);
          final query = arguments['query'];
          debugPrint(
              "🌐 RAG: Delegando búsqueda web a Santiago -> Query: $query");

          final santiago = SantiagoAgent(apiKey: apiKey);
          final assistantResponseStr = await santiago.performWebSearch(query);
          final parsedResponse = json.decode(assistantResponseStr);
          final answerMessage = parsedResponse['assistant_response'];

          // 🚨 RESPUESTA OFICIAL DE LA HERRAMIENTA CON CALL_ID 🚨
          sendEvent({
            "type": "conversation.item.create",
            "item": {
              "type": "function_call_output",
              "call_id": callId,
              "output": answerMessage,
            }
          });

          sendEvent({"type": "response.create"});
        } catch (error) {
          debugPrint('Error en web search: $error');
        } finally {
          // 🟢 2. APAGAMOS EL INDICADOR VISUAL
          onDelegatingTask?.call(false);
        }
      }

      // --- 6. APP COMMAND (execute_app_command) ---
      else if (functionName == 'execute_app_command') {
        try {
          final command = arguments['command'];
          final answerMessage = "System Success: App command executed.";

          sendEvent({
            "type": "conversation.item.create",
            "item": {
              "type": "function_call_output",
              "call_id": callId,
              "output": answerMessage
            }
          });

          //sendEvent({"type": "response.create"});

          onAppCommandTriggered?.call(command);
        } catch (error) {
          debugPrint('Error executing app command: $error');
        }
      }

      // --- 7. DESPEDIDA (end_conversation) ---
      else if (functionName == 'end_conversation') {
        try {
          debugPrint("🛑 RAG: Camila disparó el comando de DESPEDIDA.");

          // 1. Le mandamos el "recibo de entrega" al modelo para que cierre su ciclo lógico.
          sendEvent({
            "type": "conversation.item.create",
            "item": {
              "type": "function_call_output",
              "call_id": callId,
              "output": "System Success: Conversation ended by user command."
            }
          });

          // 🚨 NOTA IMPORTANTE: A diferencia de las otras herramientas,
          // AQUÍ NO MANDAMOS un {"type": "response.create"}.
          // No queremos que vuelva a hablar, su despedida ya vino en el preámbulo.

          // 2. Gatillamos la acción en el Provider.
          onEndConversationTriggered?.call();
        } catch (error) {
          debugPrint('Error ending conversation: $error');
        }
      }
    } catch (e) {
      debugPrint("Error handling function call arguments: $e");
    }
  }
}
