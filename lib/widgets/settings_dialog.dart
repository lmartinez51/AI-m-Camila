import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:aimcamila/api/gemini_websocket_service.dart';
import 'package:aimcamila/api/openai_realtime_api.dart';
import 'package:aimcamila/providers/audio_stream_provider.dart';
import 'package:aimcamila/providers/user_provider.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  String _selectedEngine = 'gemini'; // Por defecto
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentEngine();
  }

  // Cargamos la memoria para saber qué motor está usando actualmente
  Future<void> _loadCurrentEngine() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedEngine = prefs.getString('preferred_ai_engine') ?? 'openai';
      _isLoading = false;
    });
  }

  // La magia del Hot-Swap
  Future<void> _changeEngine(String newEngine) async {
    if (_selectedEngine == newEngine) {
      return; // Si toca el mismo, no hacemos nada
    }

    setState(() {
      _selectedEngine = newEngine;
    });

    // Guardamos en la memoria para la próxima vez que abra la app
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_ai_engine', newEngine);

    // Hacemos el cambio en vivo en el Provider
    if (!mounted) return;
    final audioProvider = context.read<AudioStreamProvider>();
    final userProvider = context.read<UserProvider>();

    if (newEngine == 'gemini') {
      audioProvider.switchAIEngine(GeminiWebSocketService(userProvider));
    } else {
      audioProvider.switchAIEngine(WebSocketService(userProvider));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();

    return BackdropFilter(
      filter: ImageFilter.blur(
          sigmaX: 10, sigmaY: 10), // Efecto cristal difuminado en el fondo
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1A2E), // Tu fondo Cyber-Dark
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.1), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF)
                    .withValues(alpha: 0.2), // Brillo violeta de fondo
                blurRadius: 30,
                spreadRadius: -5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // HEADER
              const Row(
                children: [
                  Icon(Icons.memory, color: Color(0xFF6C63FF), size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Neural Engine',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Select the AI brain powering Camila. The change will be applied instantly.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 24),

              // TARJETA 1: OpenAI
              _EngineCard(
                title: 'OpenAI Realtime',
                subtitle: 'Deep reasoning & expressive tone',
                icon: Icons.psychology, // Un cerebro analítico
                isSelected: _selectedEngine == 'openai',
                onTap: () => _changeEngine('openai'),
              ),
              const SizedBox(height: 16),

              // TARJETA 2: GEMINI
              _EngineCard(
                title: 'Google Gemini Live',
                subtitle: 'Ultra-fast latency & native voice',
                icon: Icons.auto_awesome, // Un destello estrellado
                isSelected: _selectedEngine == 'gemini',
                onTap: () => _changeEngine('gemini'),
              ),
              const SizedBox(height: 24),

              // BOTÓN DE CERRAR
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- EL WIDGET DE LA TARJETA ANIMADA ---
class _EngineCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _EngineCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6C63FF).withValues(
                  alpha: 0.15) // Fondo ligeramente violeta si está activo
              : Colors.white.withValues(
                  alpha: 0.03), // Fondo gris oscuro si está inactivo
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6C63FF) // Borde neón encendido
                : Colors.white.withValues(alpha: 0.05), // Borde apagado
            width: isSelected ? 2 : 1,
          ),
          // Sombra brillante solo cuando está seleccionado
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                    blurRadius: 15,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            // Icono del motor
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF6C63FF).withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? const Color(0xFF6C63FF) : Colors.white54,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            // Textos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontFamily: 'Outfit',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // El indicador de selección (El circulito con la palomita)
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF6C63FF),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
