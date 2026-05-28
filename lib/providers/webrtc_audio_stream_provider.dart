import 'dart:async';
import 'dart:io';
import 'package:aimcamila/api/did_api.dart';
import 'package:aimcamila/api/openai_webrtc_rtapi.dart';
import 'package:aimcamila/models/model.dart';
//import 'package:aimcamila/providers/audio_device_manager.dart';
import 'package:aimcamila/providers/user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class WebRTCAudioStreamProvider with ChangeNotifier {
  FlutterSoundPlayer? _player;
  //late FlutterSoundRecorder _recorder;
  final WebRTCService _webRTCService;
  //final AudioDeviceManager _audioDeviceManager;
  final Model _model;
  final UserProvider _userProvider;
  //final StreamController<Uint8List> _recordedDataController;
  Uint8List? _lastAudioChunk;
  late final ValueNotifier<bool> isPlaying = ValueNotifier(false);
  final ValueNotifier<bool> isChatbotSpeaking = ValueNotifier(false);
  bool audioReceived = false;
  //bool isVideoEnabled = false;
  final FlutterSoundHelper _helper = FlutterSoundHelper();
  Function? onAudioProcessed;
  String? _audioFilePath;
  String? get audioFilePath => _audioFilePath;
  //Variables para grabar en fase video
  final record = AudioRecorder();
  final didService = DidService();

  WebRTCAudioStreamProvider(
      this._webRTCService, this._model, this._userProvider) {
    _initialize();
    isPlaying.value = true;
  }

  Uint8List? get lastAudioChunk => _lastAudioChunk;

  // Función que se llama cuando se detecta que el chatbot ha terminado de hablar
  void onChatbotSpeaking(bool speaking) {
    isChatbotSpeaking.value = speaking;
    notifyListeners();
  }

  void stopPlaying() {
    isPlaying.value = false;
    notifyListeners();
  }

  void startPlaying() {
    isPlaying.value = true;
    notifyListeners();
  }

  void _initialize() async {
    try {
      // Configuramos el callback para guardar el audio y finalizar el player
      _webRTCService.onResponseDone = () async {
        debugPrint("Audio processing completed.");
        await Future.delayed(const Duration(milliseconds: 1000));
        startPlaying(); // Reanudar animación
        onChatbotSpeaking(false); // Detener animación del chatbot
        // El siguiente callback es solo para cuando uso video
        if (onAudioProcessed != null) {
          debugPrint("Dentro del callback");
          onAudioProcessed!();
        }
      };
      // Configuramos el callback para manejar el transcript
      _webRTCService.onOutputAudioTranscriptReceived = (transcript) {
        debugPrint("Se recibió mensaje para Model Message $transcript");
        _model.addModelMessage(transcript);
      };
      // Configuramos el callback para manejar el audio recibido
      // _webRTCService.onInputAudioTranscriptReceived = (transcript) {
      //   debugPrint("Se recibió mensaje para User Message $transcript");
      //   _model.addUserMessage(_userProvider.user!.name, transcript);
      // };
      _webRTCService.onSpeechStarted = () {
        onSpeechStarted();
      };
      _webRTCService.onSpeechStopped = () {
        onSpeechStopped();
      };
      notifyListeners();
    } catch (e) {
      debugPrint("Error during initialization: $e");
    }
  }

  void muteMicrophone() {
    //_isMicrophoneMuted = true;
    _webRTCService.muteMicrophone();
    notifyListeners();
  }

  void unmuteMicrophone() {
    //_isMicrophoneMuted = false;
    _webRTCService.unmuteMicrophone();
    notifyListeners();
  }

  Future<void> replayLastAudio() async {
    if (lastAudioChunk != null) {
      isPlaying.value = false; // Stop animation before starting new audio
      // Inicializar el player si no está ya inicializado
      if (_player == null) {
        _player = FlutterSoundPlayer();
        await _player!.openPlayer();
      }
      // Detenemos el player solo si está en uso antes de iniciar una nueva reproducción
      if (_player!.isPlaying) {
        await _player!.stopPlayer();
      }
      onChatbotSpeaking(true);
      await _player!.startPlayer(
        fromDataBuffer: lastAudioChunk!,
        codec: Codec.pcm16,
        sampleRate: 24000,
        numChannels: 1,
        whenFinished: () async {
          debugPrint("Audio playback finished.");
          await _player!
              .stopPlayer(); // Detiene el player explícitamente nuevamente
          onChatbotSpeaking(false);
          isPlaying.value = true; // Resume animation when playback finishes
        },
      );
      //onChatbotSpeaking(true); // Activamos la animacion para el chatbot
      debugPrint("Replaying last audio.");
    } else {
      debugPrint("No audio available to replay.");
    }
  }

  Future<String> convertPCMToWAV() async {
    // Obtener el directorio de documentos
    final directory = await getApplicationDocumentsDirectory();
    final wavFilePath = '${directory.path}/recording.wav';
    // Convertir el PCM a WAV
    final wavData = await _helper.pcmToWaveBuffer(
      inputBuffer: lastAudioChunk!,
      numChannels: 1,
      sampleRate: 24000,
    );
    // Escribir los datos WAV en un archivo en el directorio de documentos
    final wavFile = File(wavFilePath);
    await wavFile.writeAsBytes(wavData);
    debugPrint('Archivo WAV guardado en $wavFilePath');
    return wavFilePath; // Devuelve la ruta del archivo para usarla en otras funciones
  }

  Future<void> startRecording() async {
    try {
      unmuteMicrophone(); // Asegurarse de que el micrófono no esté silenciado
      debugPrint("Recording started.");
    } catch (e) {
      debugPrint("Error starting recording: $e");
    }
  }

  Future<void> stopRecording() async {
    try {
      muteMicrophone(); // Silenciar el micrófono después de detener la grabación
      debugPrint("Recording stopped.");
      startPlaying(); // Reanudar animación principal si estaba en pausa
      onChatbotSpeaking(false); // Detener animacion del chatbot
    } catch (e) {
      debugPrint("Error stopping recording: $e");
    }
  }

  // Métodos para manejar los eventos de interrupción de voz
  Future<void> onSpeechStarted() async {
    try {
      String userName = _userProvider.user!.name;
      _model.addUserMessage(userName, 'Mensaje de audio enviado!');
    } catch (e) {
      debugPrint("Error on speech started: $e");
    }
  }

  Future<void> onSpeechStopped() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      isPlaying.value = false; //Detener animación principal
      onChatbotSpeaking(true); //Reproducir animacion del chatbot
      debugPrint('Speech stopped');
    } catch (e) {
      debugPrint("Error on speech stopped: $e");
    }
  }

  //FASE VIDEO - AUDIO RECORDING
  Future<void> startRecordingForVideo() async {
    final localPath = (await getTemporaryDirectory()).path;
    final filePath = '$localPath/recording.wav';
    debugPrint("el filePath en startRecordingForVideo es: $filePath");
    await record.start(const RecordConfig(encoder: AudioEncoder.wav),
        path: filePath);
  }

  Future<String?> stopRecordingForVideo() async {
    try {
      await record.stop();
      final localPath = (await getTemporaryDirectory()).path;
      final filePath = '$localPath/recording.wav';
      return filePath;
    } catch (e) {
      debugPrint('Error during stopRecordingToVideo: $e');
      return null;
    }
  }

  /// Guardar el archivo de audio en almacenamiento temporal
  Future<void> saveOpenAIResponseAudio(Uint8List audioBytes) async {
    final localPath = (await getTemporaryDirectory()).path;
    final tempFile = '$localPath/audioResponse.wav';
    debugPrint("En saveOpenAI el tempFile esta en: $tempFile");
    // Guardar el archivo
    await File(tempFile).writeAsBytes(audioBytes);
    _audioFilePath = tempFile;
    notifyListeners();
  }

  // Funcion alterna de soporte en caso de que OpenAI API no genere audio
  Future<void> saveOpenAIResponseAudio2(String filePath) async {
    _audioFilePath = filePath;
    notifyListeners();
    debugPrint("Archivo de respuesta de OpenAI guardado en: $_audioFilePath");
  }

  /// Limpiar el archivo de audio guardado
  Future<void> clearOpenAIResponseAudio() async {
    if (_audioFilePath != null) {
      final file = File(_audioFilePath!);
      if (await file.exists()) {
        await file.delete();
      }
      _audioFilePath = null;
      notifyListeners();
    }
  }
}
