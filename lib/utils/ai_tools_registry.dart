// @file ai_tools_registry.dart
// @brief Centralized registry of AI tool schemas for all supported engine backends.
// @author Lorenzo Martínez
// @date 2026-04-05
// @version 1.0.0
//
// ARCHITECTURE NOTE:
// This file is the Single Source of Truth for all tool/function declarations.
// It provides two static getters — one per engine — because Gemini and OpenAI
// use distinct JSON schemas (different casing, different property shapes).
//
// To add a new tool:
//   1. Add its Gemini schema to [geminiDeclarations].
//   2. Add its OpenAI schema to [openAiTools].
//   3. Implement its execution logic in the corresponding handler mixin.

/// @brief Provides static, engine-specific tool schema declarations for
/// Gemini Live and OpenAI Realtime API injection.
class AiToolsRegistry {
  AiToolsRegistry._(); // Prevent instantiation.

  // ---------------------------------------------------------------------------
  // 🟣 GEMINI LIVE — functionDeclarations list
  // Injected into the "tools" > "functionDeclarations" array of the setup message.
  // Types use UPPERCASE (OBJECT, STRING, INTEGER) per Google's OpenAPI subset.
  // ---------------------------------------------------------------------------

  /// @brief Returns the list of [functionDeclarations] for the Gemini setup message.
  static List<Map<String, dynamic>> get geminiDeclarations => [
        // 🧠 1. MEMORIA (Guardar)
        {
          "name": "save_user_memory",
          "description":
              "Saves facts, preferences, or rules about the user. STRICT RULE: Use ONLY when the user explicitly provides NEW info.",
          "parameters": {
            "type": "OBJECT",
            "properties": {
              "category": {
                "type": "STRING",
                "description": "Short category with underscores."
              },
              "content": {
                "type": "STRING",
                "description":
                    "Saves timeless facts, preferences, or rules about the user. STRICT RULE 1: You MUST rewrite the memory from your perspective using the user's name or 'my boss' (e.g., 'Lorenzo hates Mondays' or 'My boss's favorite color is black'). NEVER use third-person robotic phrasing like 'The user said'. STRICT RULE 2: NEVER use this tool for temporal tasks/reminders; use manage_agenda instead."
              }
            },
            "required": ["category", "content"]
          }
        },

        // 🔎 2. MEMORIA (Buscar)
        {
          "name": "search_user_memory",
          "description":
              "Searches the user's long-term memory. Trigger WHENEVER the user asks about past info or asks 'Do you remember...?'.",
          "parameters": {
            "type": "OBJECT",
            "properties": {
              "query": {
                "type": "STRING",
                "description": "The specific topic or concept."
              }
            },
            "required": ["query"]
          }
        },

        // 📅 3. AGENDA
        {
          "name": "manage_agenda",
          "description":
              "Manages the user's agenda, schedule, and to-do list. Use this tool for ANY temporal task, appointment, reminder, or event tied to a specific day/time. DO NOT use this for timeless facts or permanent user preferences.",
          "parameters": {
            "type": "OBJECT",
            "properties": {
              "action": {
                "type": "STRING",
                "enum": ["add", "remove", "list"],
                "description": "The specific action to perform on the agenda."
              },
              "description": {
                "type": "STRING",
                "description":
                    "The description of the event to add. Required ONLY if action is 'add'. CRITICAL TIME RULE: If the user mentions relative time ('tomorrow', 'el lunes', 'next week'), you MUST calculate and convert it to an ABSOLUTE DATE (e.g., 'March 28, 2026') using the Current Date provided in your prompt before saving."
              },
              "event_id": {
                "type": "INTEGER",
                "description": "Event ID. Required IF action is 'remove'."
              }
            },
            "required": ["action"]
          }
        },

        // 📶 4. BLUETOOTH
        {
          "name": "search_bluetooth_devices",
          "description": "Search for nearby bluetooth devices."
        },

        // 🎮 5. APP COMMAND (execute_app_command)
        {
          "name": "execute_app_command",
          "description":
              "Executes a system-level visual or control command on the user's app interface. Use this tool when the user directly asks you to clear the screen, restart, log out, or perform a core app action.",
          "parameters": {
            "type": "OBJECT",
            "properties": {
              "command": {
                "type": "STRING",
                "enum": ["clear_chat"],
                "description": "The command string to execute."
              }
            },
            "required": ["command"]
          }
        },

        // 🛑 6. END CONVERSATION
        {
          "name": "end_conversation",
          "description":
              "Triggers when the user explicitly ends the conversation, says goodbye, dismisses you, or tells you to go to sleep. Use this tool to cleanly disconnect the active audio session."
        },
      ];

  // ---------------------------------------------------------------------------
  // 🟢 OPENAI REALTIME — tools list
  // Injected into "session" > "tools" of the session.update message.
  // Types use lowercase (object, string, integer) per OpenAI's JSON Schema spec.
  // ---------------------------------------------------------------------------

  /// @brief Returns the list of [tools] for the OpenAI session.update message.
  static List<Map<String, dynamic>> get openAiTools => [
        // 🌐 1. WEB SEARCH (Santiago sub-agent)
        {
          "type": "function",
          "name": "delegate_web_search",
          "description":
              "Delegates a complex web search or real-time data retrieval task to your sub-agent, Santiago. Use this ONLY when the user asks for current events, live stats, weather, or facts you do not know. DO NOT use this for general knowledge you already possess.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {
                "type": "string",
                "description":
                    "The highly optimized search query for Santiago to look up on the web."
              }
            },
            "required": ["query"],
            "additionalProperties": false
          }
        },

        // 📶 2. BLUETOOTH
        {
          "type": "function",
          "name": "search_bluetooth_devices",
          "description": "Search for nearby bluetooth devices.",
        },

        // 🎮 3. APP COMMAND (execute_app_command)
        {
          "type": "function",
          "name": "execute_app_command",
          "description":
              "Executes a system-level visual or control command on the user's app interface. Use this tool when the user directly asks you to clear the screen, restart, log out, or perform a core app action.",
          "parameters": {
            "type": "object",
            "properties": {
              "command": {
                "type": "string",
                "enum": ["clear_chat"],
                "description": "The command string to execute."
              }
            },
            "required": ["command"],
            "additionalProperties": false
          }
        },

        // 🧠 4. MEMORIA (Guardar)
        {
          "type": "function",
          "name": "save_user_memory",
          "description":
              "Saves important facts, preferences, rules, or data about the user for long-term memory. STRICT RULE: Use this ONLY when the user explicitly provides NEW information or facts to be saved. NEVER call this tool if the user is asking a question or requesting information about something you already know.",
          "parameters": {
            "type": "object",
            "properties": {
              "category": {
                "type": "string",
                "description":
                    "Short, lowercase category. CRITICAL RULE: If the user explicitly gives this memory a name or label (e.g., 'frase clave', 'palabra secreta', 'regla número uno'), you MUST use that exact label as the category formatted with underscores (e.g., 'frase_clave'). Otherwise, infer a logical category."
              },
              "content": {
                "type": "string",
                "description":
                    "Saves timeless facts, preferences, or rules about the user. STRICT RULE 1: You MUST rewrite the memory from your perspective using the user's name or 'my boss' (e.g., 'Lorenzo hates Mondays' or 'My boss's favorite color is black'). NEVER use third-person robotic phrasing like 'The user said'. STRICT RULE 2: NEVER use this tool for temporal tasks/reminders; use manage_agenda instead."
              }
            },
            "required": ["category", "content"],
            "additionalProperties": false
          }
        },

        // 🔎 5. MEMORIA (Buscar)
        {
          "type": "function",
          "name": "search_user_memory",
          "description":
              "Searches the user's long-term memory database. Trigger this tool WHENEVER the user asks about past personal information, preferences, or asks 'Do you remember...?'. ALWAYS verify with this tool before answering 'I don't know' or 'You didn't tell me'.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {
                "type": "string",
                "description":
                    "The specific topic, exact keyword, or vague concept the user is asking about (e.g., 'aceite', 'comida', 'evento', 'agenda')."
              }
            },
            "required": ["query"],
            "additionalProperties": false
          }
        },

        // 📅 6. AGENDA
        {
          "type": "function",
          "name": "manage_agenda",
          "description":
              "Manages the user's agenda, schedule, appointments, and to-do list. Use this tool to add new events, remove completed/canceled events, or list all current events in the agenda.",
          "parameters": {
            "type": "object",
            "properties": {
              "action": {
                "type": "string",
                "enum": ["add", "remove", "list"],
                "description": "The specific action to perform on the agenda."
              },
              "description": {
                "type": "string",
                "description":
                    "The description of the event to add. Required ONLY if action is 'add'. CRITICAL TIME RULE: If the user mentions relative time ('tomorrow', 'el lunes', 'next week'), you MUST calculate and convert it to an ABSOLUTE DATE (e.g., 'March 28, 2026') using the Current Date provided in your prompt."
              },
              "event_id": {
                "type": "integer",
                "description":
                    "The ID of the event to remove. Required ONLY if action is 'remove'."
              }
            },
            "required": ["action"],
            "additionalProperties": false
          }
        },

        // 🛑 7. END CONVERSATION
        {
          "type": "function",
          "name": "end_conversation",
          "description":
              "Triggers when the user explicitly ends the conversation, says goodbye, dismisses you, or tells you to go to sleep. Use this tool to cleanly disconnect the active audio session."
        },
      ];
}
