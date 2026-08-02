import 'dart:typed_data';

import 'package:encrypted_files/core/constants.dart';
import 'package:equatable/equatable.dart';

class EncryptedFileRef extends Equatable {
  const EncryptedFileRef({
    required this.id,
    required this.vaultId,
    required this.diskPath,
    required this.fakeName,
    required this.realNameEncrypted,
    required this.mimeEncrypted,
    required this.fileBlindTag,
    required this.sizeBytes,
    required this.folderId,
    required this.sortIndex,
    required this.createdAt,
    required this.modifiedAt,
    this.realName,
    this.mimeType,
    this.missingOnDisk = false,
  });

  final String id;
  final String vaultId;
  final String diskPath;
  final String fakeName;
  final Uint8List realNameEncrypted;
  final Uint8List mimeEncrypted;
  final Uint8List fileBlindTag;
  final int sizeBytes;
  final String? folderId;
  final int sortIndex;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// Decrypted only while a matching password is active.
  final String? realName;
  final String? mimeType;
  final bool missingOnDisk;

  MediaKind get mediaKind {
    final m = (mimeType ?? '').toLowerCase();
    final name = (realName ?? fakeName).toLowerCase();
    if (m.startsWith('image/') ||
        name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.bmp')) {
      return MediaKind.image;
    }
    if (m.startsWith('audio/') ||
        name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.m4a') ||
        name.endsWith('.aac') ||
        name.endsWith('.ogg') ||
        name.endsWith('.flac')) {
      return MediaKind.audio;
    }
    if (m.startsWith('video/') ||
        name.endsWith('.mp4') ||
        name.endsWith('.mkv') ||
        name.endsWith('.webm') ||
        name.endsWith('.avi') ||
        name.endsWith('.mov')) {
      return MediaKind.video;
    }
    if (m.contains('pdf') ||
        m.contains('text') ||
        name.endsWith('.pdf') ||
        name.endsWith('.txt') ||
        name.endsWith('.doc') ||
        name.endsWith('.docx') ||
        name.endsWith('.ppt') ||
        name.endsWith('.pptx') ||
        name.endsWith('.xls') ||
        name.endsWith('.xlsx')) {
      return MediaKind.document;
    }
    return MediaKind.other;
  }

  EncryptedFileRef copyWith({
    String? diskPath,
    String? fakeName,
    Uint8List? realNameEncrypted,
    Uint8List? mimeEncrypted,
    String? folderId,
    int? sortIndex,
    DateTime? modifiedAt,
    String? realName,
    String? mimeType,
    bool? missingOnDisk,
    int? sizeBytes,
  }) {
    return EncryptedFileRef(
      id: id,
      vaultId: vaultId,
      diskPath: diskPath ?? this.diskPath,
      fakeName: fakeName ?? this.fakeName,
      realNameEncrypted: realNameEncrypted ?? this.realNameEncrypted,
      mimeEncrypted: mimeEncrypted ?? this.mimeEncrypted,
      fileBlindTag: fileBlindTag,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      folderId: folderId ?? this.folderId,
      sortIndex: sortIndex ?? this.sortIndex,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      realName: realName ?? this.realName,
      mimeType: mimeType ?? this.mimeType,
      missingOnDisk: missingOnDisk ?? this.missingOnDisk,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'vault_id': vaultId,
        'disk_path': diskPath,
        'fake_name': fakeName,
        'real_name_enc': realNameEncrypted,
        'mime_enc': mimeEncrypted,
        'file_blind_tag': fileBlindTag,
        'size_bytes': sizeBytes,
        'folder_id': folderId,
        'sort_index': sortIndex,
        'created_at': createdAt.toIso8601String(),
        'modified_at': modifiedAt.toIso8601String(),
      };

  factory EncryptedFileRef.fromMap(Map<String, Object?> map) {
    return EncryptedFileRef(
      id: map['id']! as String,
      vaultId: map['vault_id']! as String,
      diskPath: map['disk_path']! as String,
      fakeName: map['fake_name']! as String,
      realNameEncrypted: map['real_name_enc'] as Uint8List,
      mimeEncrypted: map['mime_enc'] as Uint8List,
      fileBlindTag: map['file_blind_tag'] as Uint8List,
      sizeBytes: map['size_bytes'] as int? ?? 0,
      folderId: map['folder_id'] as String?,
      sortIndex: map['sort_index'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at']! as String),
      modifiedAt: DateTime.parse(map['modified_at']! as String),
    );
  }

  @override
  List<Object?> get props => [id];
}
