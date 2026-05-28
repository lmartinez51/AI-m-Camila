// @file main.dart
// @brief Entry point for the AI'm Camila application, handling initializations and dependency injections.
// @author Lorenzo Martínez
// @date 2026-03-30
// @version 1.0.0

import 'package:aimcamila/api/gemini_websocket_service.dart';
import 'package:aimcamila/api/openai_realtime_api.dart';
import 'package:aimcamila/api/ai_voice_service.dart';
import 'package:aimcamila/models/model.dart';
import 'package:aimcamila/navigation/route_observer.dart';
import 'package:aimcamila/pages/camila_page.dart';
import 'package:aimcamila/pages/chat_page.dart';
import 'package:aimcamila/database/objectbox_service.dart';
import 'package:aimcamila/pages/login_page/login_page.dart';
import 'package:aimcamila/providers/audio_device_manager.dart';
import 'package:aimcamila/providers/audio_stream_provider.dart';
import 'package:aimcamila/providers/user_provider.dart';
import 'package:aimcamila/providers/video_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart'; //Quizas este import sea temporal solo para debug
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

/// @brief The main execution entry point of the application.
/// Initializes Flutter bindings, UI overlays, Firebase, user preferences, ObjectBox local database, and dependency providers before running the app.
/// @return `Future<void>` Resolves when the application has been fully booted.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // --- BLOQUE DE ESTABILIDAD VISUAL ---
  // Esto evita el parpadeo negro al cambiar de pantalla
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, // Solo vertical
  ]);
  // --- BLOQUE ESTABILIDAD DE PANTALLA ---
  // Esto evita que los iconos de la barra de estado cambien de color al cambiar de pantalla
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // Barra transparente
    statusBarIconBrightness: Brightness.light, // Iconos blancos (Android)
    statusBarBrightness: Brightness.dark, // Texto blanco (iOS)
  ));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // --- 1. CARGAMOS VARIABLES DE ENTORNO PRIMERO ---
  await dotenv.load(fileName: ".env");

  // 2. LEEMOS LA MEMORIA LOCAL
  final prefs = await SharedPreferences.getInstance();
  final String savedEngine = prefs.getString('preferred_ai_engine') ?? 'openai';
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  final String initialPage = prefs.getString('initialPage') ?? 'CamilaPage';

  // 3. Cargar el estado del usuario para el resto de la app
  UserProvider userProvider = UserProvider();
  await userProvider.loadUserFromPrefs();

  // Crear instancia de AudioDeviceManager
  AudioDeviceManager audioDeviceManager = AudioDeviceManager();

  // 🔍 👇 RADIOGRAFÍA DE ARRANQUE - COPIA DESDE AQUÍ 👇 🔍
  final firebaseUser = FirebaseAuth.instance.currentUser;
  debugPrint("\n=========================================================");
  debugPrint("🚦 CONTROL DE ADUANA (DEBUG LOGS) 🚦");
  debugPrint("🔐 2. Variable isLoggedIn (SharedPreferences): $isLoggedIn");
  debugPrint(
      "👤 3. Usuario en Provider: ${userProvider.user?.email ?? 'NULO'}");
  debugPrint(
      "🔥 4. Sesión Firebase Activa: ${firebaseUser != null ? 'SI (${firebaseUser.email})' : 'NO'}");
  debugPrint("=========================================================\n");
  // 🔍 👆 HASTA AQUÍ 👆 🔍

  String initialRoute = isLoggedIn ? initialPage : '/';

  // 🛡️ REPARACIÓN DE EMERGENCIA: Inicialización de ObjectBox para Auto-Login
  if (firebaseUser != null) {
    debugPrint("🔐 Detectada sesión activa de Firebase. Abriendo bóveda...");
    try {
      objectbox = await ObjectBoxService.create(firebaseUser.uid);
      isObjectBoxReady = true;
      debugPrint("✅ ObjectBox inicializado para auto-login: ${firebaseUser.uid}");
    } catch (e) {
      debugPrint("❌ Error crítico inicializando ObjectBox en arranque: $e");
    }
  }



  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => Model()),
        ChangeNotifierProvider(create: (context) => userProvider),
        ChangeNotifierProvider(create: (context) => VideoProvider()),
        ChangeNotifierProvider(create: (context) => audioDeviceManager),
        ProxyProvider<UserProvider, AIVoiceService>(
          update: (context, userProvider, previous) {
            // Dependiendo de lo que leímos en la memoria, inyectamos el soldado correcto
            if (savedEngine == 'gemini') {
              debugPrint("🚀 Iniciando app con motor: GEMINI");
              return GeminiWebSocketService(userProvider);
            } else {
              debugPrint("🚀 Iniciando app con motor: OPENAI");
              return WebSocketService(userProvider); // Tu clase de OpenAI
            }
          },
        ),
        ChangeNotifierProvider(
          create: (context) {
            final model = context.read<Model>();
            final aiVoiceService = context.read<AIVoiceService>();
            final audioDeviceManager = context.read<AudioDeviceManager>();
            return AudioStreamProvider(
                aiVoiceService, model, userProvider, audioDeviceManager);
          },
        ),
      ],
      child: MyApp(initialRoute: initialRoute),
    ),
  );
}

/// @brief The root widget of the application.
/// Configures the material app, theme, navigation observers, and initial routes.
class MyApp extends StatelessWidget {
  final String initialRoute;

  /// @brief Constructor for the root widget.
  /// @param key The key identifier for the widget.
  /// @param initialRoute The initial navigation route determined during startup.
  const MyApp({super.key, required this.initialRoute});

  /// @brief Builds the core material application tree.
  /// @param context The build context provided by Flutter.
  /// @return Widget The instantiated MaterialApp widget.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "AI'm Camila",
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: initialRoute,
      navigatorObservers: [routeObserver],
      routes: {
        '/': (context) => const LoginPage(),
        'CamilaPage': (context) => const CamilaPage(),
        'AiChatPage': (context) => AiChatPage(
              chatHistory:
                  Provider.of<Model>(context, listen: false).camilaChatHistory,
              pageType: 'CamilaPage',
            ),
      },
    );
  }
}
