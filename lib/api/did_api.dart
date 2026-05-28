// @file did_api.dart
// @brief D-ID API integration for generating and fetching animated avatar video chunks.
// @author Lorenzo Martínez
// @date 2026-03-30
// @version 1.0.0

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

/// @brief Service orchestrating interactions with D-ID strictly for visual talking head generation.
class DidService {
  final String dIdApiKey = dotenv.env['DID_API_KEY'] ?? '';
  final String didAPIImageUrl = "https://api.d-id.com/images";
  final String didAPIAudioUrl = "https://api.d-id.com/audios";
  final String didAPITalksUrl = "https://api.d-id.com/talks";

  /// @brief Uploads a static base image to D-ID servers to prepare the avatar face space.
  /// @param imagePath The local directory path locating the target JPEG/PNG.
  /// @param name The mapping identifier to store the uploaded URL.
  /// @return `Future<String>` The remote URL allocated by D-ID.
  Future<String> uploadImage(String imagePath, String name) async {
    debugPrint("En uploadImage");

    // Verificar si el archivo existe antes de proceder
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw Exception(
          'El archivo no existe en la ruta especificada: $imagePath');
    }

    try {
      // Preparar la solicitud Multipart
      final request = http.MultipartRequest("POST", Uri.parse(didAPIImageUrl))
        ..headers['authorization'] = 'Basic $dIdApiKey'
        ..headers['accept'] = 'application/json'
        ..files.add(await http.MultipartFile.fromPath('image', imageFile.path));

      // Enviar la solicitud
      final response = await request.send();

      // Procesar la respuesta
      if (response.statusCode == 201) {
        final responseBody = await response.stream.bytesToString();
        final data = jsonDecode(responseBody);

        // Validar la URL antes de almacenarla
        if (data['url'] != null && data['url'].isNotEmpty) {
          await saveImageUrl(name, data['url']);
          debugPrint("Imagen subida exitosamente: $data");
          return data['url'];
        } else {
          throw Exception('La respuesta no contiene una URL válida.');
        }
      } else {
        // Leer el cuerpo del error
        final errorBody = await response.stream.bytesToString();
        final errorData = jsonDecode(errorBody);

        throw Exception(
          'Error al subir la imagen: ${errorData['error'] ?? 'Error desconocido'} - '
          '${errorData['description'] ?? 'Sin descripción'}',
        );
      }
    } catch (e) {
      debugPrint('Error inesperado al subir la imagen: $e');
      rethrow;
    }
  }

  /// @brief Persists the URL mapping of an uploaded face locally using JSON storage.
  /// @param name The mapped identity string.
  /// @param url The external URL provided by the cloud service.
  /// @return `Future<void>`
  Future<void> saveImageUrl(String name, String url) async {
    final localPath = (await getTemporaryDirectory()).path;
    final filePath = '$localPath/assets/imageUrls.json';
    //final directory = await getApplicationDocumentsDirectory();
    //final filePath = join(directory.path, 'assets', 'imageUrls.json');
    final file = File(filePath);

    Map<String, dynamic> imageUrls = {};
    if (await file.exists()) {
      final content = await file.readAsString();
      imageUrls = jsonDecode(content);
    }

    imageUrls[name] = url;

    await file.writeAsString(jsonEncode(imageUrls));
    debugPrint('Image URL saved successfully.');
  }

  /// @brief Pushes a temporary WAV file up to D-ID to drive the lip-syncing engine.
  /// @param filePath The local system path mapping to the recording file.
  /// @return `Future<String>` Output URL pointing to the raw audio object.
  Future<String> uploadAudioToDID(String filePath) async {
    try {
      // Verificar si el archivo existe
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('El archivo no existe en la ruta: $filePath');
      }

      // Crear la solicitud Multipart
      final uri = Uri.parse(didAPIAudioUrl);
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          'accept': 'application/json',
          'authorization': 'Basic $dIdApiKey', // Cambia con tu clave de API
        })
        ..files.add(await http.MultipartFile.fromPath(
          'audio', // Nombre del campo esperado por la API
          filePath,
        ));

      // Enviar la solicitud
      final response = await request.send();

      // Leer la respuesta
      final responseBody = await response.stream.bytesToString();
      if (response.statusCode == 201) {
        final responseData = jsonDecode(responseBody);
        debugPrint('Audio subido exitosamente: $responseData');
        return responseData[
            'url']; // Devuelve la URL de la respuesta si es necesaria
      } else {
        final responseData = jsonDecode(responseBody);
        debugPrint("Estatus de error: $response");
        throw Exception(
          'Error al subir el audio: ${responseData['error'] ?? response.reasonPhrase} - '
          '${responseData['description'] ?? 'Sin descripción'}',
        );
      }
    } catch (e) {
      debugPrint('Error al subir el audio a D-ID: $e');
      rethrow;
    }
  }

  /// @brief Triggers the master talking-head synthesis operation stitching audio and image.
  /// @param imageUrl Pre-validated URL holding the initial face frame.
  /// @param audioUrl Pre-validated URL holding the generated voice response.
  /// @return `Future<Map<String, dynamic>>` The JSON metadata holding the talk session ID.
  Future<Map<String, dynamic>> createAvatarVideo(
      String imageUrl, String audioUrl) async {
    debugPrint("En creacion de video");
    final body = jsonEncode({
      'script': {
        'type': 'audio',
        'audio_url': audioUrl,
        'reduce_noise': true,
      },
      'config': {'fluent': 'false', 'pad_audio': '0.0', 'stitch': true},
      'source_url': imageUrl,
    });

    final response = await http.post(
      Uri.parse(didAPITalksUrl),
      headers: {
        'authorization': 'Basic $dIdApiKey',
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      throw Exception(
          'Error creating avatar video: ${errorData['error']} - ${errorData['description']}');
    }
  }

  /// @brief Utility helper fracturing massive string responses to bypass native console truncations.
  /// @param message The lengthy string payload.
  void debugPrintLong(String message) {
    final pattern =
        RegExp('.{1,800}'); // Divide en fragmentos de hasta 800 caracteres
    pattern.allMatches(message).forEach((match) => debugPrint(match.group(0)));
  }

  /// @brief Polls the D-ID talks endpoint persistently until the rendering engine finishes.
  /// @param talkId The unique operation ID mapped to the ongoing synthesis chunk.
  /// @param retryCount Maximum polling loops.
  /// @param delaySeconds Rest cycle between loops.
  /// @return `Future<String?>` The final ready-to-stream video asset URL.
  Future<String?> getAvatarTalkingVideoWithPolling(String talkId,
      {int retryCount = 10, int delaySeconds = 2}) async {
    for (int i = 0; i < retryCount; i++) {
      debugPrint("Intento ${i + 1} para obtener la URL del video");

      final url = '$didAPITalksUrl/$talkId';
      debugPrint("La URL de la solicitud es: $url");

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'accept': 'application/json',
          'authorization': 'Basic $dIdApiKey',
        },
      );

      debugPrint("Estado de la respuesta: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['status'];
        final videoUrl = data['result_url'];

        debugPrintLong("La respuesta de la API es: ${response.body}");
        debugPrint("Estado del procesamiento: $status");

        if (status == 'done' && videoUrl != null) {
          debugPrint("La URL del video está lista: $videoUrl");
          return videoUrl;
        } else if (status == 'error') {
          throw Exception('Error en el procesamiento del video: $status');
        }
      } else {
        debugPrint("Error: ${response.body}");
        throw Exception(
            'Error obteniendo el video del avatar: ${response.statusCode} - ${response.reasonPhrase}');
      }

      // Esperar unos segundos antes de intentar nuevamente
      debugPrint(
          "Esperando $delaySeconds segundos antes del próximo intento...");
      await Future.delayed(Duration(seconds: delaySeconds));
    }

    // Si después de todos los intentos no se obtiene la URL, lanzamos una excepción
    throw Exception(
        'No se pudo obtener la URL del video después de $retryCount intentos');
  }

  /// @brief Retrieves the pre-cached avatar face mapping from local assets.
  /// @param name The string identity to query.
  /// @return `Future<String?>` The retrieved public URL.
  Future<String?> getImageUrl(String name) async {
    try {
      // Cargar el contenido del archivo JSON desde los assets
      final jsonString = await rootBundle.loadString('assets/imageUrls.json');

      // Decodificar el JSON a un Map
      final Map<String, dynamic> imageUrls = jsonDecode(jsonString);

      // Retornar la URL asociada al nombre, o null si no existe
      return imageUrls[name] as String?;
    } catch (e) {
      // Imprimir el error en la consola si ocurre alguna excepción
      debugPrint("Error loading imageUrls.json: $e");
      return null;
    }
  }
}
