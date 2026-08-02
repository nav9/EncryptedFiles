import 'dart:typed_data';

/// Holds sensitive bytes and wipes them on dispose.
class SecureBytes {
  SecureBytes(this._bytes);

  Uint8List? _bytes;

  Uint8List get bytes {
    final b = _bytes;
    if (b == null) {
      throw StateError('SecureBytes already wiped');
    }
    return b;
  }

  bool get isWiped => _bytes == null;

  int get length => _bytes?.length ?? 0;

  void wipe() {
    final b = _bytes;
    if (b == null) {
      return;
    }
    for (var i = 0; i < b.length; i++) {
      b[i] = 0;
    }
    _bytes = null;
  }

  SecureBytes copy() {
    final b = _bytes;
    if (b == null) {
      throw StateError('SecureBytes already wiped');
    }
    return SecureBytes(Uint8List.fromList(b));
  }
}

class SecureMemory {
  final List<SecureBytes> _tracked = [];

  SecureBytes track(Uint8List bytes) {
    final s = SecureBytes(bytes);
    _tracked.add(s);
    return s;
  }

  void wipeAll() {
    for (final s in _tracked) {
      try {
        s.wipe();
      } catch (_) {}
    }
    _tracked.clear();
  }

  void untrack(SecureBytes bytes) {
    _tracked.remove(bytes);
    bytes.wipe();
  }
}
