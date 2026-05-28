import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:typed_data';

class VideoProvider extends ChangeNotifier {
  VideoPlayerController? _loopController;
  VideoPlayerController? _tempController;
  Uint8List? _videoData1;
  Uint8List? _videoData2;
  String? tempFilePath1;
  String? tempFilePath2;
  bool _isPlayingTemp = false;
  bool _isInitialized = false;
  bool _isLoadingTemp = false;
  String? _savedVideoPath;

  // Getters para videoData1 y videoData2
  Uint8List? get videoData1 => _videoData1;
  Uint8List? get videoData2 => _videoData2;

  // Función para limpiar el VideoProvider
  void clearProvider() async {
    await _disposeControllers();
    _isPlayingTemp = false;
    _isInitialized = false;
    _isLoadingTemp = false;
    _videoData1 = null;
    _videoData2 = null;
    tempFilePath1 = null;
    tempFilePath2 = null;
    _savedVideoPath = null;
    notifyListeners();
  }

  VideoPlayerController? get currentController =>
      _isPlayingTemp ? _tempController : _loopController;

  bool get isPlayingTemp => _isPlayingTemp;
  bool get isInitialized => _isInitialized;
  bool get isLoadingTemp => _isLoadingTemp;
  bool get isPlaying =>
      (_tempController?.value.isPlaying ?? false) ||
      (_loopController?.value.isPlaying ?? false);

  Future<void> initializeFromAsset(String assetPath) async {
    await _disposeControllers();
    _loopController = VideoPlayerController.asset(assetPath);
    await _initializeController();
  }

  Future<void> initializeFromMemory1() async {
    if (_videoData1 != null) {
      await _initializeFromMemory(_videoData1!, 1);
    } else {
      throw Exception('Video data 1 not set');
    }
  }

  Future<void> initializeFromMemory2() async {
    if (_videoData2 != null) {
      await _initializeFromMemory(_videoData2!, 2);
    } else {
      throw Exception('Video data 2 not set');
    }
  }

  Future<void> _initializeFromMemory(Uint8List data, int videoIndex) async {
    await _disposeControllers();

    final tempDir = await getTemporaryDirectory();
    final tempVideoFile = File(
        '${tempDir.path}/temp_video$videoIndex.mp4'); // Usamos diferentes nombres de archivo

    await tempVideoFile.writeAsBytes(data);

    if (videoIndex == 1) {
      tempFilePath1 = tempVideoFile.path;
      _loopController = VideoPlayerController.file(tempVideoFile);
    } else {
      tempFilePath2 = tempVideoFile.path;
      _loopController = VideoPlayerController.file(tempVideoFile);
    }

    await _initializeController();
  }

  Future<void> _initializeController() async {
    await _loopController!.initialize();
    _loopController!.setLooping(true);
    _loopController!.play();
    _isInitialized = true;
    notifyListeners();
  }

  void setVideoData1(Uint8List data) {
    _videoData1 = data;
    notifyListeners();
  }

  void setVideoData2(Uint8List data) {
    _videoData2 = data;
    notifyListeners();
  }

  Future<void> playVideo(String tempVideoUrl) async {
    if (!_isPlayingTemp && _isInitialized) {
      _isLoadingTemp = true;
      notifyListeners();

      try {
        // Iniciar la carga del video temporal pero mantener el video en loop reproduciéndose
        _tempController =
            VideoPlayerController.networkUrl(Uri.parse(tempVideoUrl));
        await _tempController!.initialize();

        // Una vez que el video temporal esté listo, pausar el video en loop
        _loopController?.pause();
        _tempController!.play();
        _isPlayingTemp = true;
        _isLoadingTemp = false;

        _tempController!.addListener(_onTempVideoFinished);
        notifyListeners();
      } catch (e) {
        // Manejo de error si la URL no está disponible o no se puede acceder
        debugPrint("Error al reproducir video temporal: $e");
        // Mantener el video en loop si hay un fallo
        _loopController?.play();
        _loopController?.setLooping(true);
        _isLoadingTemp = false;
        notifyListeners();
      }
    } else {
      // Asegurar que el video en bucle siga reproduciéndose si no se cumplen las condiciones
      _loopController?.play();
      _loopController?.setLooping(true);
    }
  }

  Future<void> replayVideo() async {
    if (_savedVideoPath != null) {
      // Reproducir el video guardado
      await playVideo(_savedVideoPath!);
    } else {
      debugPrint("No saved video path available to replay.");
    }
  }

  void _onTempVideoFinished() {
    if (_tempController!.value.position >= _tempController!.value.duration) {
      _isPlayingTemp = false;
      _tempController!.removeListener(_onTempVideoFinished);
      _tempController!.dispose();
      _tempController = null;
      _loopController?.play();
      notifyListeners();
    }
  }

  Future<String> saveVideoToTempDir(String videoUrl) async {
    try {
      // Obtener el directorio temporal
      final tempDir = await getTemporaryDirectory();
      final tempVideoPath = '${tempDir.path}/temp_video.mp4';

      // Descargar el video
      final response = await http.get(Uri.parse(videoUrl));

      if (response.statusCode == 200) {
        // Guardar el video en el archivo temporal
        final file = File(tempVideoPath);
        await file.writeAsBytes(response.bodyBytes);

        debugPrint("Video guardado en: $tempVideoPath");

        // Guardar la ruta del video temporalmente descargado
        _savedVideoPath = tempVideoPath;
        return tempVideoPath;
      } else {
        debugPrint(
            'Error al descargar el video. Código de estado: ${response.statusCode}');
        return '';
      }
    } catch (e) {
      debugPrint("Error al guardar el video: $e");
      return '';
    }
  }

  Future<void> _disposeControllers() async {
    await _loopController?.dispose();
    await _tempController?.dispose();
    _loopController = null;
    _tempController = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }
}
