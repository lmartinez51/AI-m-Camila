// @file ai_tool_handler.dart
// @brief Abstract base contract for AI tool execution handlers.
// @author Lorenzo Martínez
// @date 2026-04-05
// @version 1.0.0
//
// ARCHITECTURE NOTE:
// This abstract class defines the shared callback surface that every concrete
// tool handler mixin must wire up. It decouples the WebSocket transport layer
// from the higher-level application side-effects (UI state, session lifecycle).
//
// Concrete implementations:
//   - GeminiToolHandler  (lib/api/gemini_tool_handler.dart)
//   - OpenAiToolHandler  (lib/api/openai_tool_handler.dart)

/// @brief Shared callback contract for all AI tool execution handlers.
///
/// Implementations receive raw tool-call payloads from a WebSocket stream,
/// execute the appropriate local logic, and fire these callbacks to propagate
/// side-effects to the UI layer without any direct dependency on Flutter widgets.
abstract class AiToolHandler {
  /// @brief Notifies the UI that a long-running delegated task (e.g. web search)
  /// has started or finished. Pass `true` when starting, `false` when done.
  Function(bool isDelegating)? onDelegatingTask;

  /// @brief Fired when the AI triggers the `end_conversation` tool, signalling
  /// that the active audio session should be cleanly torn down.
  Function()? onEndConversationTriggered;

  /// @brief Fired when the AI triggers `execute_app_command`, passing the
  /// resolved `command` string enum value (e.g. `"clear_chat"`) upstream.
  Function(String command)? onAppCommandTriggered;
}
