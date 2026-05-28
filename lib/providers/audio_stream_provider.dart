import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:aimcamila/api/ai_voice_service.dart';
import 'package:aimcamila/api/did_api.dart';
import 'package:aimcamila/models/model.dart';
import 'package:aimcamila/providers/audio_device_manager.dart';
import 'package:aimcamila/providers/user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// @brief Represents a single audio response item in the FIFO playback queue.
/// Each item owns a StreamController. Bytes are pushed into it as they arrive
/// from the WebSocket. When onResponseDone fires, the stream is closed.
/// The playback loop pipes this stream directly into FlutterSoundPlayer.
class _AudioItem {
  final String itemId;
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();

  _AudioItem(this.itemId);

  /// Push an incoming PCM chunk into this item's stream.
  void addChunk(Uint8List data) {
    if (!_controller.isClosed) _controller.add(data);
  }

  /// Called by onResponseDone. Closes the stream so the playback loop
  /// knows no more bytes are coming and can send FoodEof().
  void markComplete() {
    if (!_controller.isClosed) _controller.close();
  }

  /// The playback loop reads directly from this stream via await-for.
  Stream<Uint8List> get audioStream => _controller.stream;

  /// Whether the stream has already been closed (all bytes received).
  bool get isComplete => _controller.isClosed;
}

class AudioStreamProvider with ChangeNotifier {
  static const MethodChannel _systemChannel =
      MethodChannel('com.lmartinez.aimcamila/system');

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;

  StreamController<FoodData>? _audioStreamController;
  StreamController<Uint8List>? _redirectedAudioController;

  // --- EL CEREBRO INTERCAMBIABLE ---
  // Ya no depende de Gemini ni OpenAI, depende del Contrato
  AIVoiceService _aiVoiceService;

  final AudioDeviceManager _audioDeviceManager;
  final Model _model;
  final UserProvider _userProvider;

  // 🪄 NUEVO: Propiedades para identificar el motor activo en la UI
  String get activeEngineName {
    final typeName = _aiVoiceService.runtimeType.toString();
    if (typeName.contains('Gemini')) {
      return 'Google Gemini Live';
    } else if (typeName.contains('WebSocketService') || typeName.contains('OpenAI') || typeName.contains('OpenAi')) {
      return 'OpenAI GPT Realtime';
    }
    return 'Realtime Engine';
  }

  bool get isGemini => _aiVoiceService.runtimeType.toString().contains('Gemini');

  final StreamController<Uint8List> _recordedDataController =
      StreamController<Uint8List>.broadcast();

  final FlutterSoundHelper _helper = FlutterSoundHelper();

  Uint8List? _lastAudioChunk;
  String? _audioFilePath;

  final ValueNotifier<bool> isPlaying = ValueNotifier(true);
  final ValueNotifier<bool> isChatbotSpeaking = ValueNotifier(false);

  bool isVideoEnabled = false;
  bool _shouldRedirectAudioToRecorder = false;

  bool _muteLiveAudio = false;
  final ValueNotifier<bool> isReplaying = ValueNotifier(false);

  bool _isMicrophoneMuted = true;
  bool _initialized = false;
  bool _playerReady = false;
  bool _wasMicOpenBeforeChatPage = false;
  final ValueNotifier<bool> isDelegatingTask = ValueNotifier(false);

  // 🔒 STATE LOCK: Prevents the auto-resume loop from hijacking the mic after a goodbye.
  bool _isSystemHangingUp = false;
  // 🪄 NUEVO: Bandera para esperar a que termine de hablar antes de minimizar
  bool _isPendingMinimize = false;

  // --- FIFO AUDIO QUEUE (Phase 1: AudioQueueManager) ---
  final Queue<_AudioItem> _audioQueue = Queue();
  _AudioItem? _activeQueueItem; // The item currently receiving delta bytes
  bool _isPlaybackLoopRunning = false;

  Function? onAudioProcessed;

  final record = AudioRecorder();
  final didService = DidService();

  AudioStreamProvider(
    this._aiVoiceService,
    this._model,
    this._userProvider,
    this._audioDeviceManager,
  ) {
    _initialize();
    _setupSystemChannelListener();
  }

  // ==========================================================
  // NUEVA FUNCIÓN: EL INTERRUPTOR DE MOTORES
  // ==========================================================
  void switchAIEngine(AIVoiceService newEngine) async {
    debugPrint("🔄 Cambiando motor de IA...");

    // 1. ANESTESIA GENERAL: Apagamos el micrófono para siempre en esta sesión
    if (!_isMicrophoneMuted || _recorder?.isRecording == true) {
      muteMicrophone();
      await stopRecording();
      // NO enviamos commit aquí para no generar el error rojo de OpenAI
    }
    await _stopPlayer();

    // 2. Apagamos el motor viejo
    try {
      _aiVoiceService.cancelResponse();
      _aiVoiceService.closeConnection();
    } catch (e) {
      debugPrint("Silencing old engine error: $e");
    }

    // 3. Desconectamos los cables (callbacks)
    _aiVoiceService.onAudioDeltaReceived = null;
    _aiVoiceService.onResponseDone = null;
    _aiVoiceService.onOutputAudioTranscriptReceived = null;
    _aiVoiceService.onSpeechStarted = null;
    _aiVoiceService.onSpeechStopped = null;

    // 4. Esperamos medio segundo para que Android libere los puertos
    await Future.delayed(const Duration(milliseconds: 500));

    // 5. Instalamos el motor nuevo
    _aiVoiceService = newEngine;

    // 6. Reconectamos los cables al motor nuevo
    _bindWebSocketCallbacks();

    // 7. Encendemos el motor nuevo (¡En silencio!)
    _aiVoiceService.connect();

    // ELIMINAMOS EL PASO 8. El micrófono se queda APAGADO.
    // El usuario tendrá que presionar el botón de "Llamar" para iniciar la plática.
    await _initializePlayer();
    debugPrint(
        "✅ Motor de IA cambiado exitosamente. Esperando acción del usuario.");
    notifyListeners();
  }

  /* ================= INIT ================= */

  Future<void> _initialize() async {
    try {
      if (_recorder != null) return;

      _recorder = FlutterSoundRecorder();
      _player = FlutterSoundPlayer();

      await _recorder!.openRecorder();
      await _player!.openPlayer();

      _setupAudioStreamController();

      _redirectedAudioController = StreamController<Uint8List>();
      _redirectedAudioController!.stream.listen((data) {
        if (_shouldRedirectAudioToRecorder) {
          _recordedDataController.add(data);
        }
      });

      await _initializePlayer();

      _recordedDataController.stream.listen(processAudioData);

      _bindWebSocketCallbacks();

      _aiVoiceService.connect();

      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint("AudioStreamProvider init error: $e");
    }
  }

  void _setupAudioStreamController() {
    if (_audioStreamController != null && !_audioStreamController!.isClosed) {
      _audioStreamController!.close();
    }

    _audioStreamController = StreamController<FoodData>.broadcast();
    _audioStreamController!.stream.listen((food) {
      final sink = _player?.foodSink;
      if (sink != null) {
        sink.add(food);
      }
    });
  }

  Future<void> _initializePlayer() async {
    if (_playerReady || _player == null) return;

    // 🛡️ MATA-FANTASMAS: Lo marcamos como listo ANTES del await para evitar llamadas múltiples
    _playerReady = true;

    try {
      await _player!.startPlayerFromStream(
        codec: Codec.pcm16,
        sampleRate: 24000,
        numChannels: 1,
      );
    } catch (e) {
      _playerReady = false;
      debugPrint("Error initializing player: $e");
    }
  }

  // --- INYECCIÓN DE HEADER WAV ---
  // (La mantenemos aquí porque el reproductor la necesita, sin importar el motor)
  Uint8List _addWavHeader(Uint8List rawAudio) {
    int channels = 1;
    int sampleRate = 24000;
    int byteRate = sampleRate * channels * 2;
    int totalDataLen = rawAudio.length + 36;
    int audioDataLen = rawAudio.length;

    var header = ByteData(44);
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, totalDataLen, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, audioDataLen, Endian.little);

    var builder = BytesBuilder();
    builder.add(header.buffer.asUint8List());
    builder.add(rawAudio);
    return builder.toBytes();
  }

  // ==========================================================
  // NUEVA FUNCIÓN: EL DESPERTADOR DEL WAKE WORD
  // ==========================================================
  Future<void> handleWakeWordGreeting() async {
    await Future.delayed(const Duration(milliseconds: 2000));

    if (_aiVoiceService.isConnected) {
      debugPrint("🎤 Wake Word: Disparando saludo invisible...");

      // 🔓 QUITAMOS EL SEGURO DE LA PUERTA:
      // Como el usuario acaba de invocar a Camila con la voz, es una nueva plática.
      // Esto permite que el 'onResponseDone' abra el micro normalmente al terminar el saludo.
      _isSystemHangingUp = false;

      // 1. Mandamos el saludo
      _aiVoiceService.triggerInvisibleResponse(
          "The user just woke you up via the 'Oye Camila' voice command. Wake up energetically, greet them briefly in Spanish acting as Camila, and wait for their command.");
    }
  }

  /* ================= WEBSOCKET CALLBACKS ================= */

  void _bindWebSocketCallbacks() {
    // ─── FIFO Queue: Incoming delta bytes ────────────────────────────────────
    // Append bytes to the active queue item. If there is no active item yet
    // (race before the first response.created event), open one automatically.
    _aiVoiceService.onAudioDeltaReceived = (Uint8List audio) {
      if (!_initialized) return;

      if (_shouldRedirectAudioToRecorder) {
        processAndRedirectAudio(audio);
        return;
      }

      // Create an implicit queue item if the server skipped response.created
      _activeQueueItem ??=
          _AudioItem('implicit-${DateTime.now().millisecondsSinceEpoch}');
      if (!_audioQueue.contains(_activeQueueItem)) {
        _audioQueue.add(_activeQueueItem!);
      }
      _activeQueueItem!.addChunk(audio);

      // Ensure the playback loop is running
      _ensurePlaybackLoop();
    };

    // ─── FIFO Queue: Response complete ───────────────────────────────────────
    // Mark the active item as fully received so the playback loop can
    // transition cleanly. Do NOT stop the player or re-init the stream here.
    _aiVoiceService.onResponseDone = (Uint8List audio) async {
      _saveAllAudio(audio);
      // Signal the active queue item that no more bytes are coming
      _activeQueueItem?.markComplete();
      _activeQueueItem = null; // Next response will create a new item
    };

    _aiVoiceService.onInputAudioTranscriptReceived = (text) {
      // 🛡️ 1. EL ESCÁNER DE FANTASMAS (Nivel Servidor)
      final lowerText = text.toLowerCase().trim();
      final RegExp asianCharacters =
          RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]');

      if (asianCharacters.hasMatch(text) ||
          lowerText.contains("subtitles by") ||
          lowerText
              .contains("mbc") || // Por si el reportero coreano ataca de nuevo
          lowerText == "thank you." ||
          lowerText == "thank you" ||
          lowerText == "thanks.") {
        debugPrint(
            "🛡️ Fantasma interceptado desde el servidor: $text. ¡Abortando audio de IA!");

        // 🚨 2. EL KILL-SWITCH: Le decimos a OpenAI que cancele el audio que está generando
        _aiVoiceService.cancelResponse();

        // 3. Restauramos la UI para que no se quede trabada
        onChatbotSpeaking(false);
        isPlaying.value = true;

        return; // Matamos el proceso aquí, no llega al Model
      }

      // Si es un humano real, lo mandamos al doble fondo
      _model.updateLastUserHiddenTranscript(text);
      // 🟢 NUEVO: ¡EL CADENERO DEJA PASAR EL TEXTO REAL A LA PANTALLA!
      _addSafeUserBubble(text);
    };

    _aiVoiceService.onOutputAudioTranscriptReceived = (text) {
      _model.isLoading.value = false;
      _model.addModelMessage(text);
      notifyListeners();
    };

    _aiVoiceService.onSpeechStarted = onSpeechStarted;
    _aiVoiceService.onSpeechStopped = onSpeechStopped;

    // --- NUEVO: Conectamos el cable de Santiago al interruptor visual ---
    _aiVoiceService.onDelegatingTask = (bool isDelegating) {
      // Usamos el método que creamos hace rato para actualizar la UI
      setDelegatingTask(isDelegating);
    };

    _aiVoiceService.onEndConversationTriggered = () {
      debugPrint("📞 La IA solicitó colgar la llamada. Ejecutando relevo...");
      terminateConversation(); // <-- ¡Llamamos a la nueva función destructiva!
    };

    _aiVoiceService.onAppCommandTriggered = (String command) async {
      if (command == 'clear_chat') {
        debugPrint("🧹 APP COMMAND: Ejecutando clear_chat (Full Reset)...");
        _model.isWipingMemory = true; // 🔒 UI QUARANTINE ACTIVATED
        await _model.clearChatHistoryUI();

        debugPrint(
            "⏳ Esperando a que termine el preámbulo de borrado de memoria...");
        // Retraso solicitado: 1.5 a 2 segundos
        await Future.delayed(const Duration(milliseconds: 1800));

        _aiVoiceService.clearContext();
        _model.isWipingMemory = false; // 🔓 UI QUARANTINE DEACTIVATED

        // 🛑 DISCONNECT MIC & FORCE IDLE: Let the user intentionally restart when ready
        await _resetToIdleState();
        debugPrint(
            "💤 App successfully transitioned to completely idle state post-reset.");
      }
    };

    // 🚨 FATAL ERROR: Triggered by server-side codes 1011 / 1008.
    // Resets the app to idle WITHOUT minimizing — the user stays in the foreground.
    _aiVoiceService.onFatalErrorTriggered = () {
      debugPrint(
          "🚨 [PROVIDER] Fatal server error. Resetting to idle (no minimize).");
      _handleFatalError();
    };
  }

  /* ================= AUDIO FLOW ================= */

  void _addSafeUserBubble(String text) {
    final user = _userProvider.user;
    if (user == null) return;

    final chatHistory = _model.camilaChatHistory.value;

    // EL CADENERO: Revisa si el último mensaje es exactamente igual
    if (chatHistory.isNotEmpty) {
      final lastMessage = chatHistory.last;
      if (lastMessage['role'] == 'user' && lastMessage['content'] == text) {
        debugPrint(
            "🛡️ Escudo Anti-Hipo: Burbuja duplicada de '$text' eliminada.");
        return; // Es un clon, lo botamos
      }
    }

    // Si pasó el filtro, lo publicamos
    _model.addUserMessage(user.name, text);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIFO PLAYBACK LOOP
  // ─────────────────────────────────────────────────────────────────────────

  /// @brief Starts the playback loop if it is not already running.
  /// Safe to call multiple times — only one loop runs concurrently.
  void _ensurePlaybackLoop() {
    if (_isPlaybackLoopRunning) return;
    _isPlaybackLoopRunning = true;
    _playbackLoop();
  }

  /// @brief FIFO playback loop. Strictly event-driven — zero polling, zero timers.
  ///
  /// For each item:
  ///   1. Starts a fresh FlutterSoundPlayer stream session.
  ///   2. Pipes the item's `Stream<Uint8List>` into the player via `await for`.
  ///   3. Sends FoodEof() when the stream closes (onResponseDone fired).
  ///   4. Awaits the player's native `whenFinished` callback via a Completer.
  ///   5. Advances to the next item — no guessing, no timers.
  Future<void> _playbackLoop() async {
    try {
      while (_audioQueue.isNotEmpty || _activeQueueItem != null) {
        // If we're waiting for the first chunk of the next item, yield briefly.
        if (_audioQueue.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 5));
          continue;
        }

        final item = _audioQueue.first;

        // --- SILENT BYPASS (Restored Logic) ---
        if (_muteLiveAudio) {
          // Drain the stream silently to wait for network completion and avoid memory leaks.
          // The audio bytes are already being captured natively by _saveAllAudio for the Replay buffer.
          await for (final _ in item.audioStream) {}
          _audioQueue.removeFirst();

          if (_audioQueue.isEmpty && _activeQueueItem == null) {
            await Future.delayed(const Duration(milliseconds: 20));
          }
          continue; // Skip the hardware player entirely for this item
        }

        // ── 1. Prepare hardware ──────────────────────────────────────────────
        if (!isChatbotSpeaking.value) {
          onChatbotSpeaking(true);
          isPlaying.value = false;
          if (!_audioDeviceManager.areHeadphonesConnected) {
            await stopRecordingAndMute();
          }
        }

        // Each item gets a clean player session to guarantee proper FoodEof handling.
        await _stopPlayer();

        // Completer resolved by the player's native whenFinished callback.
        final itemDone = Completer<void>();

        await _player!.startPlayerFromStream(
          codec: Codec.pcm16,
          sampleRate: 24000,
          numChannels: 1,
          whenFinished: () {
            _playerReady = false;
            if (!itemDone.isCompleted) itemDone.complete();
          },
        );
        _playerReady = true;

        // ── 2. Pipe stream → player ──────────────────────────────────────────
        // `await for` suspends here until the StreamController is closed
        // by markComplete() (triggered by onResponseDone). No polling.
        await for (final chunk in item.audioStream) {
          _player!.foodSink!.add(FoodData(chunk));
        }

        // ── 3. Signal hardware end-of-audio ───────────────────────────────────
        // In flutter_sound 9.x, we push a FoodEvent to the stream. This callback
        // executes natively ONLY after all preceding FoodData (audio chunks)
        // have been fully drained by the hardware.
        _player!.foodSink!.add(FoodEvent(() async {
          await _player!.stopPlayer(); // Triggers whenFinished naturally
        }));

        // ── 4. Await native hardware completion ───────────────────────────────
        await itemDone.future;

        // ── 5. Advance ────────────────────────────────────────────────────────
        _audioQueue.removeFirst();
        debugPrint(
            "✅ [QUEUE] Item '${item.itemId}' finished naturally. Remaining: ${_audioQueue.length}");

        // Small guard: give the server a microtask to enqueue the next item
        // before we check if the queue is truly empty (back-to-back responses).
        if (_audioQueue.isEmpty && _activeQueueItem == null) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }
    } catch (e) {
      debugPrint("❌ [PLAYBACK LOOP ERROR]: $e");
      // If the loop fatals out (e.g. startPlayer throws), clear the corrupted queue
      // so the finally block can guarantee a clean teardown.
      _audioQueue.clear();
      _activeQueueItem = null;
    } finally {
      _isPlaybackLoopRunning = false;
      // GUARANTEED TEARDOWN: Execute exactly when the queue naturally empties,
      // or if it was cleared due to a fatal error.
      if (_audioQueue.isEmpty && _activeQueueItem == null) {
        await _onAllItemsPlayed();
      }
    }
  }

  /// @brief Called when the queue fully empties. Handles mic open, state reset,
  /// and pending minimize — the responsibilities previously inside onResponseDone.
  Future<void> _onAllItemsPlayed() async {
    isPlaying.value = true;
    onChatbotSpeaking(false);

    await _stopPlayer();

    // 🪄 Pending minimize from a farewell (end_conversation tool)
    if (_isPendingMinimize) {
      debugPrint("💤 Despedida completada. Minimizando la app...");
      _isPendingMinimize = false;
      _minimizeApp();
      return;
    }

    // Re-open microphone when ready
    if (!_muteLiveAudio && !_audioDeviceManager.areHeadphonesConnected) {
      await startRecordingAndUnmute();
    }

    _setupAudioStreamController();
    onAudioProcessed?.call();
  }

  /// @brief Immediately aborts the playback loop and clears the queue.
  /// Closes all pending item streams so any active await-for loop terminates.
  Future<void> interruptPlayback() async {
    debugPrint(
        "⚡ [QUEUE] Interruption received. Clearing ${_audioQueue.length} pending items.");

    // Close all pending item streams so the await-for in _playbackLoop unblocks.
    for (final item in _audioQueue) {
      item.markComplete();
    }
    _audioQueue.clear();
    _activeQueueItem?.markComplete();
    _activeQueueItem = null;
    _isPlaybackLoopRunning = false;

    await _stopPlayer();
    onChatbotSpeaking(false);
    isPlaying.value = true;
    _setupAudioStreamController();
  }

  // Legacy redirect path for the D-ID video integration, unchanged
  Future<void> processAudioChunk(Uint8List audioData) async {
    // This path is now only used by processAndRedirectAudio for the D-ID video stream.
    // Direct live audio is handled by the FIFO queue via onAudioDeltaReceived.
    if (isVideoEnabled || _muteLiveAudio) return;
    debugPrint(
        "[processAudioChunk] Called outside queue path — routing to stream directly.");
    final sink = _player?.foodSink;
    if (sink != null &&
        _audioStreamController != null &&
        !_audioStreamController!.isClosed) {
      _audioStreamController!.add(FoodData(audioData));
    }
  }

  Future<void> processAndRedirectAudio(Uint8List audioData) async {
    try {
      isPlaying.value = false;
      _redirectedAudioController?.add(audioData);
      onChatbotSpeaking(true);
    } catch (e) {
      debugPrint("Error redirecting audio: $e");
    }
  }

  void processAudioData(Uint8List data) {
    if (_isMicrophoneMuted) return;

    // El motor activo sabe cómo enviar el chunk
    _aiVoiceService.sendAudioChunk(data);
  }

  /* ================= STATE ================= */

  void setDelegatingTask(bool isDelegating) {
    if (isDelegatingTask.value == isDelegating) return;
    isDelegatingTask.value = isDelegating;
  }

  // ==========================================================
  // FAIL-SAFE & IDLE LOGIC
  // ==========================================================

  /// @brief Forces all audio hardware and visual states into a dead-stop idle mode
  /// without closing or minimizing the app. Requires explicit user action to resume.
  Future<void> _resetToIdleState() async {
    _isSystemHangingUp = true;

    muteMicrophone();
    await stopRecording();

    onChatbotSpeaking(false);
    isDelegatingTask.value = false;
    isPlaying.value =
        true; // 'true' structurally equates to 'listening/idle' in the UI

    await _stopPlayer();
    await _initializePlayer();
    _setupAudioStreamController();

    _isPendingMinimize = false;
    notifyListeners();
  }

  /// @brief Called when Gemini sends a fatal close code (1011 Quota Exceeded /
  /// 1008 Policy Violation). Cleanly stops the recorder, mutes the mic, and
  /// resets every visual state to idle while keeping the app fully in the foreground.
  Future<void> _handleFatalError() async {
    await _resetToIdleState();

    _fatalErrorMessage =
        "Límite de conexión alcanzado. Revisa tu facturación o inténtalo más tarde.";

    notifyListeners();
    debugPrint("✅ [PROVIDER] App reset to idle. User can manually retry.");
  }

  /// @brief Exposes and auto-clears the last fatal error message for
  /// widgets to display as a SnackBar. Returns `null` if no error is pending.
  String? consumeFatalErrorMessage() {
    final msg = _fatalErrorMessage;
    _fatalErrorMessage = null;
    return msg;
  }

  // 🚨 Internal storage for the pending fatal-error notification message.
  String? _fatalErrorMessage;

  void onChatbotSpeaking(bool speaking) {
    if (isChatbotSpeaking.value == speaking) return;

    // 🚀 Asignación directa y cruda
    isChatbotSpeaking.value = speaking;
  }

  void unmuteMicrophone() {
    _isMicrophoneMuted = false;

    // 🛡️ ESCUDO ANTI-CRASH: Diferimos la notificación al siguiente ciclo.
    // Esto evita que Flutter haga crash si la app se está "despertando" y dibujando.
    Future.microtask(() {
      notifyListeners();
    });
  }

  void muteMicrophone() {
    _isMicrophoneMuted = true;

    Future.microtask(() {
      notifyListeners();
    });
  }

  bool get isMicrophoneMuted => _isMicrophoneMuted;
  Uint8List? get lastAudioChunk => _lastAudioChunk;
  String? get audioFilePath => _audioFilePath;

  void setRedirectAudioToRecorder(bool value) {
    _shouldRedirectAudioToRecorder = value;
    notifyListeners();
  }

  void _saveAllAudio(Uint8List audioData) {
    _lastAudioChunk = audioData;
    notifyListeners();
  }

  /* ================= RECORDING ================= */

  Future<void> startRecording() async {
    if (!_initialized || _recorder == null) {
      await _initialize();
      if (!_initialized) return;
    }

    if (_recorder!.isRecording) {
      await _recorder!.stopRecorder();
    }

    try {
      await _recorder!.startRecorder(
        toStream: _recordedDataController.sink,
        codec: Codec.pcm16,
        sampleRate: 24000,
        numChannels: 1,
      );
    } catch (e) {
      debugPrint("Error starting recorder: $e");
    }
  }

  Future<void> stopRecording() async {
    if (_recorder?.isRecording == true) {
      await _recorder!.stopRecorder();
    }
  }

  // 🛡️ SECURITY LOCK APLICADO: Solo las llamadas con forceStart: true abren el micrófono cuando está bloqueado
  Future<void> startRecordingAndUnmute({bool forceStart = false}) async {
    // 🛡️ SECURITY GUARD: Abort if the system is currently hanging up and this is an auto-resume request.
    if (_isSystemHangingUp && !forceStart) {
      debugPrint(
          "🔒 SYSTEM LOCKED: Auto-resume aborted because the conversation was ended.");
      return;
    }

    // If it's a forced start (new explicit conversation), disengage the lock.
    if (forceStart) {
      _isSystemHangingUp = false;
    }

    _muteLiveAudio = false;

    // 🛡️ GATILLO DE SUTURA INVISIBLE
    if (!_aiVoiceService.isConnected) {
      debugPrint("🔌 Túnel caído detectado. Reconstruyendo en background...");
      await _aiVoiceService.connect();
      await Future.delayed(
          const Duration(milliseconds: 500)); // Damos tiempo al session.update

      final recentContext = _model.getRecentContextForReconnection(limit: 5);
      if (recentContext.isNotEmpty) {
        _aiVoiceService.injectReconnectionContext(recentContext);
      }
    }

    unmuteMicrophone();
    await startRecording();
    await _initializePlayer();
    debugPrint("🛑 ACCION: BOTÓN LLAMAR PRESIONADO");
  }

  Future<void> stopRecordingAndMute() async {
    muteMicrophone();
    await stopRecording();

    // Le avisamos al motor activo que ya terminamos de hablar
    _aiVoiceService.commitUserAudioTurn();
    debugPrint("🛑 ACCION: BOTÓN COLGAR PRESIONADO (Turno Cedido)");
  }

  // ==========================================================
  // NUEVO: EL DESPERTADOR POST-BACKGROUND (Android 16 Safe)
  // ==========================================================
  void _setupSystemChannelListener() {
    _systemChannel.setMethodCallHandler((call) async {
      if (call.method == 'onWakeUp') {
        debugPrint("🔊 WAKE UP RECEIVED FROM NATIVE ANDROID!");
        // 1. Tactile UX confirmation
        HapticFeedback.lightImpact();

        // 2. Synchronize all internal state variables and connections
        await resetStateOnWakeUp();

        // 3. Trigger the AI greeting
        await handleWakeWordGreeting();
      }
    });
  }

  Future<void> resetStateOnWakeUp() async {
    debugPrint(
        "☀️ Resetting Provider State for Foreground (Force Reconnection)...");

    // 1. EL "DESTROZA-FANTASMAS": Inmediatamente desbloqueamos los interruptores maestros
    // para que no haya rastro de la última sesión terminada/minimizada.
    _isSystemHangingUp = false;
    _isPendingMinimize = false;

    // 2. Reset visual state and animations
    onChatbotSpeaking(false);
    isDelegatingTask.value = false;
    isPlaying.value = true;

    // 🔌 RECONEXIÓN FORZOSA (Meticulous approach for Android 16)
    // No confiamos en '.isConnected' porque el socket puede ser un zombi.
    // Cerramos explícitamente y abrimos uno nuevo.
    debugPrint("🔌 Kill & Rebirth: Forcefully re-establishing WebSocket...");
    _aiVoiceService.closeConnection();
    await _aiVoiceService.connect();

    // Damos tiempo al driver de red y al handshake inicial
    await Future.delayed(const Duration(milliseconds: 800));

    // 4. SUTURA INVISIBLE: Inyectamos el hilo de la plática anterior
    final recentContext = _model.getRecentContextForReconnection(limit: 5);
    if (recentContext.isNotEmpty) {
      _aiVoiceService.injectReconnectionContext(recentContext);
    }

    // 5. Freshen up the audio stack: stop and re-init to clear any stalled buffers
    await _stopPlayer();
    await _initializePlayer();
    _setupAudioStreamController();

    notifyListeners();
  }

  // 🛡️ HELPER: Minimizar la app sin matar el engine (Android 16 Friendly)
  Future<void> _minimizeApp() async {
    try {
      debugPrint("📉 Minimizando aplicación (moveTaskToBack)...");
      await _systemChannel.invokeMethod('minimizeApp');
    } on PlatformException catch (e) {
      debugPrint("❌ Error al minimizar la app: ${e.message}");
      // Fallback a SystemNavigator.pop si falla el canal custom,
      // aunque en Android 16 esto sea destructivo.
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    }
  }

  Future<void> _restartWakeWordIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    bool isEnabled = prefs.getBool('wake_word_enabled') ?? false;

    if (isEnabled) {
      debugPrint("⏳ [RELEVO]: Esperando liberación de hardware...");

      // 🛡️ ANTI-RACE CONDITION:
      // Le damos 600ms al driver de Android para que destruya el objeto AudioRecord
      // y libere el Mutex del micrófono antes de que Kotlin intente inicializar Vosk.
      await Future.delayed(const Duration(milliseconds: 600));

      try {
        debugPrint("🔄 [RELEVO]: Invocando Wake Word Service en Kotlin...");
        // Aquí llamas a tu MethodChannel específico
        // await WakeWordPlugin.startListening();
      } catch (e) {
        debugPrint("❌ [RELEVO]: Error al reiniciar Vosk: $e");
      }
    }
  }

  Future<void> terminateConversation() async {
    _isSystemHangingUp = true;
    onChatbotSpeaking(false);

    muteMicrophone();

    // 🔔 CRÍTICO: Esperar a que el hardware se detenga realmente
    await stopRecording();

    _isPendingMinimize = true;

    debugPrint("🛑 ACCION: SESIÓN FINALIZADA. Iniciando relevo...");

    // El delay de seguridad ya vive dentro de esta función
    await _restartWakeWordIfNeeded();

    // 🛡️ RED DE SEGURIDAD (Safety Timeout):
    // Si en 4 segundos el motor de IA no dispara el 'onResponseDone'
    // (porque se quedó trabado el stream), minimizamos la app a la fuerza.
    Future.delayed(const Duration(seconds: 4), () {
      if (_isPendingMinimize) {
        debugPrint(
            "💤 Timeout de seguridad alcanzado (terminate). Minimizando app...");
        _isPendingMinimize = false;
        _minimizeApp();
      }
    });
  }

  /* ================= PLAYER ================= */

  Future<void> _stopPlayer() async {
    if (_playerReady && _player != null) {
      await _player!.stopPlayer();
      _playerReady = false;
    }
  }

  Future<void> replayLastAudio() async {
    if (isReplaying.value) {
      await _stopPlayer();
      isReplaying.value = false;
      onChatbotSpeaking(false);
      isPlaying.value = true;
      await _initializePlayer();
      return;
    }

    if (_lastAudioChunk == null || _player == null) return;

    // 1. LA FOTOGRAFÍA: Guardamos cómo estaba el micrófono antes de tocar nada
    bool wasMicMutedBeforeReplay = _isMicrophoneMuted;

    await _stopPlayer();
    isReplaying.value = true;
    onChatbotSpeaking(true);
    isPlaying.value = false;

    // 2. Apagamos el micro por seguridad (para que no haya eco de la bocina al micro)
    if (!_audioDeviceManager.areHeadphonesConnected) {
      stopRecordingAndMute();
    }

    Uint8List safeWavAudio = _addWavHeader(_lastAudioChunk!);

    await _player!.startPlayer(
      fromDataBuffer: safeWavAudio,
      codec: Codec.pcm16WAV,
      whenFinished: () async {
        isReplaying.value = false;
        onChatbotSpeaking(false);
        isPlaying.value = true;

        // 3. LA RESTAURACIÓN INTELIGENTE
        if (!_muteLiveAudio && !_audioDeviceManager.areHeadphonesConnected) {
          // Solo lo volvemos a encender si la fotografía dice que ESTABA encendido
          if (!wasMicMutedBeforeReplay) {
            await startRecordingAndUnmute();
          }
          // Si estaba apagado, simplemente no hacemos nada y se queda apagado.
        }

        await _initializePlayer();
      },
    );
  }

  Future<void> playSavedAudio() async {
    if (_audioFilePath == null) return;

    final file = File(_audioFilePath!);
    if (!await file.exists()) return;

    await _stopPlayer();
    onChatbotSpeaking(true);
    isPlaying.value = false;

    if (!_audioDeviceManager.areHeadphonesConnected) {
      stopRecordingAndMute();
    }

    try {
      await _player!.startPlayer(
        fromURI: _audioFilePath,
        codec: Codec.pcm16WAV,
        whenFinished: () async {
          onChatbotSpeaking(false);
          isPlaying.value = true;

          if (!_muteLiveAudio && !_audioDeviceManager.areHeadphonesConnected) {
            await startRecordingAndUnmute();
          }

          await _initializePlayer();
        },
      );
    } catch (e) {
      debugPrint("Error playing saved audio: $e");
      onChatbotSpeaking(false);
      isPlaying.value = true;
      await _initializePlayer();
    }
  }

  Future<void> sendMediaMessage(String? text, String? base64Image,
      String userName, String pageType) async {
    try {
      // 🛡️ SUTURA INVISIBLE: Si el túnel se cayó, reconectamos antes de mandar la foto
      if (!_aiVoiceService.isConnected) {
        debugPrint(
            "🔌 Túnel caído detectado. Reconstruyendo en background antes de enviar imagen...");
        await _aiVoiceService.connect();
        await Future.delayed(const Duration(milliseconds: 500));

        final recentContext = _model.getRecentContextForReconnection(limit: 5);
        if (recentContext.isNotEmpty) {
          _aiVoiceService.injectReconnectionContext(recentContext);
        }
      }

      // 1. ANESTESIA TEMPORAL OBLIGATORIA (El escudo para la imagen)
      // Apagamos el micrófono SIEMPRE que enviemos multimedia, sin importar en qué página estemos.
      // Esto evita que el ruido de fondo interrumpa a la IA mientras "mira" la foto.
      await stopRecordingAndMute();

      // 2. Mantenemos el estado de la página para saber qué hacer DESPUÉS
      // Si es CamilaPage, _muteLiveAudio = false permitirá que el micrófono
      // se vuelva a encender automáticamente en la función `onResponseDone`.
      if (pageType == 'CamilaPage') {
        _muteLiveAudio = false;
      } else {
        _muteLiveAudio = true;
      }

      await _stopPlayer();
      await _initializePlayer(); // Dejamos la bocina lista para su respuesta
      onChatbotSpeaking(false);

      String? thumbnailData;
      if (base64Image != null) {
        // Obligamos al código a ESPERAR a que la miniatura se genere
        thumbnailData = await _model.getThumbnailBase64(base64Image);
      }

      // Ahora mandamos todo en un solo movimiento atómico
      _model.addUserMessage(userName, text ?? '',
          imageBase64: base64Image, thumbnailBase64: thumbnailData);

      _model.textController.clear();
      _model.isLoading.value = true;

      // 3. Mandamos la imagen al motor activo
      _aiVoiceService.sendUserMessageAndImage(text, base64Image);
    } catch (e) {
      debugPrint("Error enviando mensaje multimedia: $e");
      _model.isLoading.value = false;
    }
  }

  /* ================= SPEECH ================= */

  Future<void> onSpeechStarted(dynamic itemId) async {
    if (_muteLiveAudio) return;

    // ⚡ USER INTERRUPTION: Flush the entire audio queue immediately.
    // This prevents preambles from a cancelled response from playing after the user speaks.
    await interruptPlayback();

    if (!_audioDeviceManager.areHeadphonesConnected) {
      await startRecordingAndUnmute();
    } else {
      await _initializePlayer();
    }
  }

  void onSpeechStopped() {
    if (!_audioDeviceManager.areHeadphonesConnected) {
      stopRecordingAndMute();
    }
    _initializePlayer();
  }

  /* ================= VIDEO & UTIL ================= */

  Future<void> startRecordingForVideo() async {
    final localPath = (await getTemporaryDirectory()).path;
    final filePath = '$localPath/recording.wav';
    await record.start(const RecordConfig(encoder: AudioEncoder.wav),
        path: filePath);
  }

  Future<String?> stopRecordingForVideo() async {
    try {
      await record.stop();
      final localPath = (await getTemporaryDirectory()).path;
      return '$localPath/recording.wav';
    } catch (_) {
      return null;
    }
  }

  Future<void> saveOpenAIResponseAudio(Uint8List audioBytes) async {
    final localPath = (await getTemporaryDirectory()).path;
    final tempFile = '$localPath/audioResponse.wav';
    await File(tempFile).writeAsBytes(audioBytes);
    _audioFilePath = tempFile;
    notifyListeners();
  }

  Future<void> saveOpenAIResponseAudio2(String filePath) async {
    _audioFilePath = filePath;
    notifyListeners();
  }

  Future<void> clearOpenAIResponseAudio() async {
    if (_audioFilePath == null) return;
    final file = File(_audioFilePath!);
    if (await file.exists()) {
      await file.delete();
    }
    _audioFilePath = null;
    notifyListeners();
  }

  Future<String> convertPCMToWAV() async {
    final directory = await getApplicationDocumentsDirectory();
    final wavFilePath = '${directory.path}/recording.wav';
    final wavData = await _helper.pcmToWaveBuffer(
      inputBuffer: lastAudioChunk!,
      numChannels: 1,
      sampleRate: 24000,
    );
    final wavFile = File(wavFilePath);
    await wavFile.writeAsBytes(wavData);
    return wavFilePath;
  }

  Future<void> retryRecording() async {
    await startRecording();
  }

  Future<void> enterChatPage() async {
    debugPrint("🛑 ACCION: ENTRANDO A CHAT PAGE (Continuidad de Audio)");

    // 1. Tomamos la fotografía del micrófono
    _wasMicOpenBeforeChatPage = !_isMicrophoneMuted;

    // 2. Apagamos SOLO el micrófono por privacidad mientras lees.
    // Así Camila no te interrumpe si haces ruido.
    if (!_isMicrophoneMuted) {
      await stopRecordingAndMute();
    }

    // 3. ¡LA MAGIA!
    // - NO llamamos a _stopPlayer(). Dejamos que el audio fluya.
    // - NO cambiamos _muteLiveAudio. Si estaba recibiendo audio en vivo, que termine.
  }

  void exitChatPage() async {
    debugPrint("🛑 ACCION: SALIENDO DE CHAT PAGE (Restaurando estado)");

    if (_wasMicOpenBeforeChatPage) {
      debugPrint("🔄 El micrófono estaba ABIERTO antes. Restaurando...");
      _muteLiveAudio = false; // Permitimos que fluya el audio
      if (!_audioDeviceManager.areHeadphonesConnected) {
        // 🛡️ REGLA ESPECIAL: Al restaurar un estado previo de navegación explícito, pasamos el candado.
        await startRecordingAndUnmute(forceStart: true);
      }
    } else {
      debugPrint("🔄 El micrófono estaba CERRADO. Se queda cerrado.");
      _muteLiveAudio =
          true; // 🛡️ NUEVO: Bloqueamos el auto-reopen para que no prenda solo al terminar de hablar
    }
  }

  /* ================= DISPOSE ================= */

  @override
  void dispose() {
    try {
      _aiVoiceService.cancelResponse();
      _aiVoiceService.closeConnection();
      _aiVoiceService.onEndConversationTriggered = null;
      _aiVoiceService.onFatalErrorTriggered = null; // 🚨 Memory safety
    } catch (e) {
      debugPrint("Error cerrando servicio de IA en dispose: $e");
    }

    _recordedDataController.close();
    _audioStreamController?.close();
    _redirectedAudioController?.close();

    _recorder?.closeRecorder();
    _player?.closePlayer();

    super.dispose();
  }
}
