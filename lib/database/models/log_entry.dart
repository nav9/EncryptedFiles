import 'package:encrypted_files/core/constants.dart';
import 'package:equatable/equatable.dart';

class LogEntry extends Equatable {
  const LogEntry({
    required this.id,
    required this.level,
    required this.tag,
    required this.message,
    required this.createdAt,
  });

  final int? id;
  final LogLevel level;
  final String tag;
  final String message;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'level': level.name,
        'tag': tag,
        'message': message,
        'created_at': createdAt.toIso8601String(),
      };

  factory LogEntry.fromMap(Map<String, Object?> map) {
    return LogEntry(
      id: map['id'] as int?,
      level: LogLevel.values.firstWhere(
        (e) => e.name == map['level'],
        orElse: () => LogLevel.info,
      ),
      tag: map['tag']! as String,
      message: map['message']! as String,
      createdAt: DateTime.parse(map['created_at']! as String),
    );
  }

  @override
  List<Object?> get props => [id, createdAt, message];
}
