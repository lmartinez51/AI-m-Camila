🚀 Plan de Actualización: AI'm Camila (Target: Gemma 4)
Objetivo: Reemplazar el cerebro actual (Gemma 3 - 1B) por Gemma 4 mediante inyección directa ADB, manteniendo la estabilidad nativa de MediaPipe.

Las Especificaciones Estrictas del Archivo:

Modelo Base: Gemma 4 (Prioridad a versiones Uncensored o Fine-tuned por la comunidad para evadir los filtros éticos corporativos).

Formato Obligatorio: .task (Tiene que ser el paquete MediaPipe GenAI completo. Debe contener internamente los pesos, el tokenizer.spm y los metadatos. Rechazar cualquier .gguf, .litertlm crudo o .bin suelto).

Cuantización: INT4 (Crucial para que la GPU del Pixel 10 Pro no drene la batería ni sature la RAM).

Tamaño Esperado: Entre 1.2 GB y 2.0 GB.

Radares de Búsqueda (Dónde revisar cada semana):

HuggingFace: Buscar explícitamente los términos gemma-4 task, gemma-4 mediapipe, o gemma-4 tflite int4. (Ir directo a la pestaña Files and versions para confirmar la extensión .task).

Google AI Edge / Kaggle: Revisar las versiones oficiales de TensorFlow Lite para la familia Gemma.

Protocolo de Inyección (Cero Riesgos):
Cuando el archivo esté asegurado, ejecutar la rutina de pizarra limpia en la terminal para evitar el error de caché corrupta de flutter_gemma:

Borrar archivo viejo: adb shell rm /storage/emulated/0/Android/data/com.lmartinez.aimcamila/files/gemma.task

Empujar archivo nuevo: adb push <nuevo_modelo>.task /storage/emulated/0/Android/data/com.lmartinez.aimcamila/files/gemma.task

Abrir candados: adb shell chmod 777 /storage/emulated/0/Android/data/com.lmartinez.aimcamila/files/gemma.task

Ejecutar la función de purga en Dart (FlutterGemma.uninstallModel) antes del reinicio.
