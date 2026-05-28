import 'package:objectbox/objectbox.dart';

@Entity()
class EpisodicMemory {
  @Id()
  int id = 0;

  // El párrafo generado por gpt-4o-mini (ej. "Ayer platicamos sobre el proyecto...")
  String summary;

  // Clave para la caducidad y para saber cuál es el más reciente
  @Property(type: PropertyType.date)
  DateTime createdAt;

  EpisodicMemory({
    this.id = 0,
    required this.summary,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
