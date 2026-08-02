import 'dart:typed_data';

import 'package:encrypted_files/crypto/native_bindings.dart';
import 'package:equatable/equatable.dart';

class VaultModel extends Equatable {
  const VaultModel({
    required this.id,
    required this.salt,
    required this.blindIndex,
    required this.kdf,
    required this.createdAt,
    this.isDecoy = false,
  });

  final String id;
  final Uint8List salt;
  final Uint8List blindIndex;
  final KdfParams kdf;
  final DateTime createdAt;

  /// If true, this vault entry belongs to the plausible-deniability password.
  /// Unlocking with a decoy password triggers a fake "corrupt bytes" message.
  final bool isDecoy;

  Map<String, Object?> toMap() => {
        'id': id,
        'salt': salt,
        'blind_index': blindIndex,
        'kdf_mem': kdf.memBlocks,
        'kdf_passes': kdf.passes,
        'kdf_lanes': kdf.lanes,
        'created_at': createdAt.toIso8601String(),
        'is_decoy': isDecoy ? 1 : 0,
      };

  factory VaultModel.fromMap(Map<String, Object?> map) {
    return VaultModel(
      id: map['id']! as String,
      salt: map['salt'] as Uint8List,
      blindIndex: map['blind_index'] as Uint8List,
      kdf: KdfParams(
        memBlocks: map['kdf_mem'] as int,
        passes: map['kdf_passes'] as int,
        lanes: map['kdf_lanes'] as int,
      ),
      createdAt: DateTime.parse(map['created_at']! as String),
      isDecoy: (map['is_decoy'] as int? ?? 0) != 0,
    );
  }

  @override
  List<Object?> get props => [id];
}
