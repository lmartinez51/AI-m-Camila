import 'package:objectbox/objectbox.dart';

@Entity()
class AgendaEvent {
  @Id()
  int id;

  String description;
  DateTime createdAt;

  AgendaEvent({
    this.id = 0,
    required this.description,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
