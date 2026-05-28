import 'package:aimcamila/objectbox.g.dart';
import 'package:aimcamila/models/semantic_memory.dart';
import 'package:aimcamila/models/episodic_memory.dart';
import 'package:aimcamila/models/agenda_event.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

late ObjectBoxService objectbox;
bool isObjectBoxReady = false;

class ObjectBoxService {
  /// El Store es el "disco duro" abierto. Solo debe haber uno en toda la app.
  late final Store store;
  static ObjectBoxService? _instance;
  static Store? _store;

  // Modificamos el constructor privado para que corra la escoba al instanciarse
  ObjectBoxService._create(this.store) {
    _runEpisodicSweeper();
  }

  /// Enciende el motor de ObjectBox (Versión Protegida)
  static Future<ObjectBoxService> create(String uid) async {
    // 1. Si ya tenemos una instancia activa para este mismo usuario, la devolvemos
    if (_instance != null && _store != null && !_store!.isClosed()) {
      return _instance!;
    }

    // 2. Buscamos el lugar seguro
    final docsDir = await getApplicationDocumentsDirectory();
    final dbDirectory = p.join(docsDir.path, "camila-memory-db-$uid");

    // 3. 🛡️ LA PROTECCIÓN: Intentamos abrir, pero si ya está abierta, nos "acoplamos"
    if (Store.isOpen(dbDirectory)) {
      _store = Store.attach(getObjectBoxModel(), dbDirectory);
    } else {
      _store = await openStore(directory: dbDirectory);
    }

    _instance = ObjectBoxService._create(_store!);
    return _instance!;
  }

  /// 🧹 Ejecuta la Orden 66: Vacía TODAS las cajas de recuerdos de la app
  void clearAllMemory() {
    // 1. Borramos Memoria Semántica (Hechos y Reglas)
    final semanticCount = store.box<SemanticMemory>().removeAll();

    // 2. Borramos Memoria Episódica (Resúmenes de pláticas)
    final episodicCount = store.box<EpisodicMemory>().removeAll();

    // 3. Borramos la Agenda (Eventos temporales)
    final agendaCount = store.box<AgendaEvent>().removeAll();

    final totalDeleted = semanticCount + episodicCount + agendaCount;

    debugPrint(
        "🗑️ ObjectBox Orden 66 Ejecutada: Se han borrado $totalDeleted registros en total.");
    debugPrint("   - Semántica: $semanticCount");
    debugPrint("   - Episódica: $episodicCount");
    debugPrint("   - Agenda: $agendaCount");
  }

  /// 🧹 La nueva Función Escoba (Caducador) para la memoria a corto plazo
  /// Se ejecuta automáticamente y de forma silenciosa al abrir la base de datos.
  void _runEpisodicSweeper() {
    final box = store.box<EpisodicMemory>();

    final query = box
        .query()
        .order(EpisodicMemory_.createdAt, flags: Order.descending)
        .build();

    final allMemories = query.find();
    query.close();

    // Si no hay nada, o solo hay un resumen (la bandeja mínima), no hacemos nada
    if (allMemories.length <= 1) return;

    final now = DateTime.now();
    final idsToDelete = <int>[];

    // Empezamos en el índice 1 para proteger siempre el resumen más reciente (índice 0)
    for (var i = 1; i < allMemories.length; i++) {
      final memory = allMemories[i];
      if (now.difference(memory.createdAt).inHours >= 72) {
        idsToDelete.add(memory.id);
      }
    }

    if (idsToDelete.isNotEmpty) {
      box.removeMany(idsToDelete);
      debugPrint(
          "🧹 ObjectBox: Escoba Episódica borró ${idsToDelete.length} resúmenes antiguos.");
    }
  }

  /// Obtiene la memoria episódica más reciente (la de hoy, si existe)
  EpisodicMemory? getMostRecentEpisodicMemory() {
    final box = store.box<EpisodicMemory>();
    final query = box
        .query()
        .order(EpisodicMemory_.createdAt, flags: Order.descending)
        .build();

    final result = query.findFirst();
    query.close();
    return result;
  }

  /// Inserta o actualiza una memoria episódica
  void upsertEpisodicMemory(EpisodicMemory memory) {
    store.box<EpisodicMemory>().put(memory);
  }

  // ==========================================
  // 📅 SISTEMA DE AGENDA DEDICADO
  // ==========================================

  /// Agrega un nuevo evento a la agenda
  void addAgendaEvent(String description) {
    final box = store.box<AgendaEvent>();
    box.put(AgendaEvent(description: description));
    debugPrint("📅 AGENDA: Evento agregado -> $description");
  }

  /// Borra un evento específico usando su ID
  bool removeAgendaEvent(int id) {
    final box = store.box<AgendaEvent>();
    final success = box.remove(id);
    if (success) {
      debugPrint("📅 AGENDA: Evento con ID $id eliminado exitosamente.");
    } else {
      debugPrint("📅 AGENDA: Error, no se encontró el evento con ID $id.");
    }
    return success;
  }

  /// Devuelve todos los eventos pendientes en la agenda
  List<AgendaEvent> getAllAgendaEvents() {
    final box = store.box<AgendaEvent>();
    return box.getAll();
  }

  /// 🚪 Cierra la bóveda actual de forma segura
  void closeStore() {
    if (!store.isClosed()) {
      store.close();
      debugPrint("🚪 ObjectBox: Bóveda cerrada de forma segura.");
    }
  }
}
