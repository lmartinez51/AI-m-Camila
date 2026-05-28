import 'package:objectbox/objectbox.dart';

@Entity()
class SemanticMemory {
  @Id()
  int id = 0;

  // El @Index hace que las búsquedas por categoría sean ultrarrápidas.
  // Es clave para nuestra regla del UPSERT.
  // Ejemplo: "hija", "escala_modelado", "equipo_futbol"
  @Index()
  String category;

  // El recuerdo real en texto.
  // Ejemplo: "Giovanna", "1/7", "FC Barcelona"
  String content;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  // NOTA FUTURA: Cuando ObjectBox libere los vectores al 100% en Flutter,
  // aquí agregaremos algo como:
  // @HnswIndex(dimensions: 1536)
  // @Property(type: PropertyType.floatVector)
  // List<double>? embedding;

  SemanticMemory({
    this.id = 0,
    required this.category,
    required this.content,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();
}
