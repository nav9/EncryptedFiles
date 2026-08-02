import 'package:equatable/equatable.dart';

class VirtualFolder extends Equatable {
  const VirtualFolder({
    required this.id,
    required this.vaultId,
    required this.nameEncrypted,
    required this.parentId,
    required this.sortIndex,
    required this.createdAt,
    this.name,
    this.fileCount = 0,
  });

  final String id;
  final String vaultId;
  final List<int> nameEncrypted;
  final String? parentId;
  final int sortIndex;
  final DateTime createdAt;
  final String? name;
  final int fileCount;

  VirtualFolder copyWith({
    String? name,
    int? fileCount,
    String? parentId,
    int? sortIndex,
    List<int>? nameEncrypted,
  }) {
    return VirtualFolder(
      id: id,
      vaultId: vaultId,
      nameEncrypted: nameEncrypted ?? this.nameEncrypted,
      parentId: parentId ?? this.parentId,
      sortIndex: sortIndex ?? this.sortIndex,
      createdAt: createdAt,
      name: name ?? this.name,
      fileCount: fileCount ?? this.fileCount,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'vault_id': vaultId,
        'name_enc': nameEncrypted,
        'parent_id': parentId,
        'sort_index': sortIndex,
        'created_at': createdAt.toIso8601String(),
      };

  factory VirtualFolder.fromMap(Map<String, Object?> map) {
    return VirtualFolder(
      id: map['id']! as String,
      vaultId: map['vault_id']! as String,
      nameEncrypted: map['name_enc'] as List<int>,
      parentId: map['parent_id'] as String?,
      sortIndex: map['sort_index'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at']! as String),
    );
  }

  @override
  List<Object?> get props => [id];
}
