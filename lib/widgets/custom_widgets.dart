import 'dart:convert';
import 'package:aimcamila/database/objectbox_service.dart';
import 'package:aimcamila/models/episodic_memory.dart';
import 'package:aimcamila/models/model.dart';
import 'package:aimcamila/models/semantic_memory.dart';
import 'package:aimcamila/pages/login_page/auth_manager.dart';
import 'package:aimcamila/providers/user_provider.dart';
import 'package:aimcamila/providers/audio_stream_provider.dart';
import 'package:aimcamila/widgets/settings_dialog.dart';
import 'package:aimcamila/api/ai_voice_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class CustomButton extends StatelessWidget {
  final Color iconColor;
  final double iconSize;
  final IconData icon;
  final ImageSource source;
  final String pageType;
  final FocusNode focusNode;

  const CustomButton({
    super.key,
    required this.iconColor,
    required this.iconSize,
    required this.icon,
    required this.source,
    required this.pageType,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: iconColor),
      iconSize: iconSize,
      onPressed: () async {
        final model = Provider.of<Model>(context, listen: false);
        final userProvider = Provider.of<UserProvider>(context, listen: false);

        // 1. Obtener la imagen en base64 usando tu función existente
        String? imageBase64 = await model.getImage(source: source);

        if (imageBase64 != null) {
          // 2. Mostrar el diálogo moderno de previsualización
          if (!context.mounted) return;
          showDialog(
            context: context,
            barrierDismissible:
                false, // Obliga al usuario a enviar o cancelar explícitamente
            builder: (BuildContext dialogContext) {
              return Dialog(
                backgroundColor:
                    const Color(0xFF1E1F2A), // Fondo de tarjeta oscura
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                insetPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 24), // Da margen para respirar
                child: SingleChildScrollView(
                  // <-- ESTE WIDGET ES LA SOLUCIÓN MÁGICA
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize
                          .min, // Hace que la columna ocupe solo lo necesario
                      children: [
                        // Header del Dialog
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Attach Image",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white54),
                              onPressed: () {
                                model.textController.clear();
                                Navigator.pop(
                                    dialogContext); // Cancela y cierra
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Previsualización de la Imagen
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16.0),
                          child: Image.memory(
                            // SEPARAMOS EL PREFIJO Y TOMAMOS SOLO LA DATA PURA
                            base64Decode(imageBase64.contains(',')
                                ? imageBase64.split(',').last
                                : imageBase64),
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Caja de texto para el Prompt
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(
                                0xFF161722), // Mismo color del chat canvas
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: TextField(
                            controller: model.textController,
                            focusNode: focusNode,
                            style: const TextStyle(
                                color: Colors.white, fontFamily: 'Outfit'),
                            maxLines: 4,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Add a message for Camila...',
                              hintStyle: TextStyle(
                                  color: Colors.white30, fontFamily: 'Outfit'),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Botón Enviar con Gradiente
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            onPressed: () async {
                              final text = model.textController.text;
                              focusNode.unfocus();

                              // 1. Cerramos el modal inmediatamente
                              Navigator.pop(dialogContext);

                              // 2. Usamos nuestro nuevo puente RealTime
                              final audioProvider =
                                  Provider.of<AudioStreamProvider>(context,
                                      listen: false);
                              await audioProvider.sendMediaMessage(
                                  text,
                                  imageBase64,
                                  userProvider.user!.name,
                                  pageType);
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("Send to Camila",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'Outfit',
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                SizedBox(width: 8),
                                Icon(Icons.send_rounded,
                                    color: Colors.white, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }
      },
    );
  }
}

class SendButton extends StatelessWidget {
  final Color iconColor;
  final double iconSize;
  final String pageType;
  final FocusNode focusNode;

  const SendButton({
    super.key,
    required this.iconColor,
    required this.iconSize,
    required this.pageType,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.send, color: iconColor),
      iconSize: iconSize,
      onPressed: () async {
        final model = Provider.of<Model>(context, listen: false);
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final audioProvider =
            Provider.of<AudioStreamProvider>(context, listen: false);

        final text = model.textController.text;

        if (text.isNotEmpty) {
          focusNode.unfocus();

          // Usamos el puente RealTime (pasando null en la imagen porque es puro texto)
          await audioProvider.sendMediaMessage(
              text, null, userProvider.user!.name, 'AiChatPage');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please enter some text to send.',
                style: TextStyle(
                    fontFamily: 'Outfit', color: Colors.white, fontSize: 13),
              ),
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFF6C63FF),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }
}

class MenuButton extends StatelessWidget {
  final AuthManager authManager = AuthManager();

  MenuButton({super.key});

  Future<void> logoutAndExit(BuildContext context) async {
    // 1. Mostrar Loading Overlay Profesional que bloquea interacción
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1F2A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF6C63FF)),
                  SizedBox(height: 24),
                  Text(
                    "Securely saving assistant memory context.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Outfit',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Safely closing the session. This will take a few seconds.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Outfit',
                      fontSize: 13,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    final model = Provider.of<Model>(context, listen: false);

    try {
      if (model.camilaChatHistory.value.isNotEmpty) {
        await model.compressEpisodicMemory();
      }

      // 🔍 👇 MEGA-RADIOGRAFÍA DE TODA LA MEMORIA (TEMPORAL) 👇 🔍
      try {
        debugPrint(
            "\n=========================================================");
        debugPrint("🚀 INICIANDO VOLCADO TOTAL DE MEMORIA (DEBUG) 🚀");
        debugPrint(
            "=========================================================\n");

        // 1. MEMORIA EPISÓDICA (Resúmenes de conversaciones del día)
        final episodicBox = objectbox.store.box<EpisodicMemory>();
        final episodicMemories = episodicBox.getAll();
        debugPrint(
            "🧠 --- MEMORIA EPISÓDICA (TOTAL: ${episodicMemories.length}) --- 🧠");
        if (episodicMemories.isEmpty) {
          debugPrint("   [Vacía]");
        } else {
          for (var m in episodicMemories) {
            debugPrint(
                "   📅 Fecha: ${m.createdAt.toIso8601String().split('T')[0]} | ID: ${m.id}");
            debugPrint("   📝 Resumen: ${m.summary}");
            debugPrint(
                "   - - - - - - - - - - - - - - - - - - - - - - - - - - - - -");
          }
        }
        debugPrint("\n");

        // 2. MEMORIA SEMÁNTICA (Hechos, preferencias, reglas - ej. Color negro, Graduación)
        final semanticBox = objectbox.store.box<SemanticMemory>();
        final semanticMemories = semanticBox.getAll();
        debugPrint(
            "📚 --- MEMORIA SEMÁNTICA (TOTAL: ${semanticMemories.length}) --- 📚");
        if (semanticMemories.isEmpty) {
          debugPrint("   [Vacía]");
        } else {
          for (var m in semanticMemories) {
            debugPrint("   🏷️ Categoría: [${m.category}] | ID: ${m.id}");
            debugPrint("   📌 Contenido: ${m.content}");
            debugPrint(
                "   - - - - - - - - - - - - - - - - - - - - - - - - - - - - -");
          }
        }
        debugPrint("\n");

        // 3. AGENDA (Eventos temporales y tareas)
        final agendaEvents = objectbox.getAllAgendaEvents();
        debugPrint(
            "📅 --- AGENDA Y EVENTOS (TOTAL: ${agendaEvents.length}) --- 📅");
        if (agendaEvents.isEmpty) {
          debugPrint("   [Vacía]");
        } else {
          for (var e in agendaEvents) {
            debugPrint("   ⏰ ID: ${e.id}");
            debugPrint("   📌 Descripción: ${e.description}");
            debugPrint(
                "   - - - - - - - - - - - - - - - - - - - - - - - - - - - - -");
          }
        }

        debugPrint(
            "\n=========================================================");
        debugPrint("🛑 FIN DEL VOLCADO DE MEMORIA 🛑");
        debugPrint(
            "=========================================================\n");
      } catch (e) {
        debugPrint("❌ Error al imprimir la radiografía global: $e");
      }
      // 🔍 👆 FIN DE LA MEGA-RADIOGRAFÍA 👆 🔍

      model.updateChatHistory([]);

      if (!context.mounted) return;

      // 2. Cerrar sesión (AuthManager maneja la redirección y limpia el historial de navegación)
      await authManager.signOut(context);
    } catch (e) {
      debugPrint("❌ Error durante el Sign-Out: $e");
      if (context.mounted) {
        // En caso de error, quitamos el loading screen para que el usuario no quede atrapado
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to sign out securely. Please try again.",
                style: TextStyle(fontFamily: 'Outfit', color: Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // --- EL DIÁLOGO NUCLEAR (Estilo Dark Mode) ---
  void _showNuclearDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1F2A), // Fondo de tarjeta oscura
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6B6B)),
              SizedBox(width: 8),
              Text(
                'Erase Memory?',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'This will permanently delete all facts, preferences, and data saved by Camila. This action is irreversible. Are you sure, Boss?',
            style: TextStyle(
                color: Colors.white70, fontFamily: 'Outfit', height: 1.4),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey, fontFamily: 'Outfit')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B6B), // Rojo coral
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () {
                // 0. LA CORRECCIÓN: Usamos dialogContext en lugar del context fantasma
                final scaffoldMessenger = ScaffoldMessenger.of(dialogContext);

                // 1. Ejecutamos el borrado en ObjectBox
                objectbox.clearAllMemory();

                // 2. Cerramos el modal
                Navigator.of(dialogContext).pop();

                // 3. Mostramos el éxito
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.delete_sweep, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text("All memories have been erased.",
                            style: TextStyle(fontFamily: 'Outfit')),
                      ],
                    ),
                    backgroundColor: const Color(0xFF4CAF50), // Verde de éxito
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Yes, Erase',
                  style: TextStyle(
                      fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F2A),
        borderRadius: BorderRadius.circular(16.0),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.0),
      ),
      child: IconButton(
        icon: const Icon(Icons.more_vert, color: Colors.white, size: 28),
        tooltip: 'Main Menu',
        onPressed: () {
          _showMainMenuBottomSheet(context);
        },
      ),
    );
  }

  void _showMainMenuBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1F2A), // Mismo color de tu UI
      isScrollControlled: true, // Permite que crezca si agregamos más cosas
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pill handle (la rayita de arriba para deslizar)
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // CATEGORÍA 1: INTELIGENCIA Y CONTEXTO
                _buildBottomSheetItem(
                  context: context,
                  icon: Icons.cleaning_services_outlined,
                  text: 'Clear Context (RAM)',
                  onTap: () {
                    Navigator.pop(context); // Cerramos el menú

                    // 1. Limpiamos la Pantalla de Inmediato (Full UI Reset)
                    Provider.of<Model>(context, listen: false)
                        .clearChatHistoryUI();

                    // 2. Reiniciamos el "Cerebro" WSS (RAM Reset)
                    final aiService =
                        Provider.of<AIVoiceService>(context, listen: false);
                    aiService.clearContext();

                    // 3. Feedback Visual de éxito (Opcional, pero da buena UX)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                                'Memory and screen cleared. Full Reset complete.',
                                style: TextStyle(fontFamily: 'Outfit')),
                          ],
                        ),
                        backgroundColor: const Color(0xFF6C63FF),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),

                const Divider(color: Colors.white24, height: 32),

                // CATEGORÍA 2: DEVELOPER TOOLS
                _buildCategoryTitle('DEVELOPER TOOLS'),
                _buildBottomSheetItem(
                  context: context,
                  icon: Icons.psychology_outlined,
                  text: "Camila's Brain (DB)",
                  onTap: () {
                    Navigator.pop(context);
                    _showComingSoonSnackBar(context); // Sustituir por tu lógica
                  },
                ),
                _buildBottomSheetItem(
                  context: context,
                  icon: Icons.bluetooth,
                  text: 'Bluetooth Devices',
                  onTap: () {
                    Navigator.pop(context);
                    _showComingSoonSnackBar(context);
                  },
                ),

                const Divider(color: Colors.white24, height: 32),

                // CATEGORÍA 3: SYSTEM & DANGER ZONE
                _buildCategoryTitle('SYSTEM'),
                _buildBottomSheetItem(
                  context: context,
                  icon: Icons.settings_outlined,
                  text: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.6),
                      builder: (context) =>
                          const SettingsDialog(), // Tu diálogo actual
                    );
                  },
                ),
                _buildBottomSheetItem(
                  context: context,
                  icon: Icons.delete_forever,
                  text: 'Erase Memory',
                  color: const Color(0xFFFF6B6B),
                  onTap: () {
                    Navigator.pop(context);
                    _showNuclearDialog(context); // Tu botón nuclear actual
                  },
                ),
                _buildBottomSheetItem(
                  context: context,
                  icon: Icons.logout,
                  text: 'Sign Out',
                  color: const Color(0xFFFF6B6B),
                  onTap: () {
                    //Navigator.pop(context);
                    logoutAndExit(context); // Tu lógica actual
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // WIDGET HELPER: Títulos de Categoría
  Widget _buildCategoryTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, left: 16.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          fontFamily: 'Outfit', // Usando tu fuente
        ),
      ),
    );
  }

  // WIDGET HELPER: Items del BottomSheet
  Widget _buildBottomSheetItem({
    required BuildContext context,
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return ListTile(
      leading: Icon(icon, color: color, size: 24),
      title: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontFamily: 'Outfit',
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      hoverColor: Colors.white.withValues(alpha: 0.05),
      splashColor: Colors.white.withValues(alpha: 0.1),
    );
  }

  // WIDGET HELPER: Tu SnackBar reutilizable
  void _showComingSoonSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.construction, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Feature coming soon!',
                style: TextStyle(fontFamily: 'Outfit')),
          ],
        ),
        backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
