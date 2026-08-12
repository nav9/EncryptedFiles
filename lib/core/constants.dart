/// Shared constants and paths for EncryptedFiles.
class AppConstants {
  AppConstants._();

  static const String appName = 'EncryptedFiles';
  static const String appFolderName = 'encrypted_files';
  static const String databaseFileName = 'tracker.db';
  static const String lockFileName = 'app.lock';
  static const String logTableMaxRows = '500';

  static const int keySize = 32;
  static const int saltSize = 16;
  static const int nonceSize = 24;
  static const int macSize = 16;
  static const int blindSize = 32;

  static const int defaultChunkBytes = 32 * 1024;
  static const List<int> allowedChunkSizes = [
    8 * 1024,
    16 * 1024,
    32 * 1024,
    64 * 1024,
    128 * 1024,
    256 * 1024,
    512 * 1024,
    1024 * 1024,
  ];

  /// Argon2id defaults tuned for low-RAM Android devices.
  static const int argon2MemBlocks = 16384; // 16 MiB
  static const int argon2Passes = 2;
  static const int argon2Lanes = 1;

  /// Anti-bruteforce delay for unrecognized passwords (seconds).
  static const int unrecognizedPasswordDelaySec = 3;

  static const int maxLogEntries = 500;

  static const String magic = 'EFENCv01';
}

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

enum MediaKind {
  image,
  audio,
  video,
  document,
  other,
}

enum SortMode {
  manual,
  nameAsc,
  nameDesc,
  createdAsc,
  createdDesc,
  modifiedAsc,
  modifiedDesc,
}
