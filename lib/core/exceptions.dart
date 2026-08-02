class EfException implements Exception {
  EfException(this.message, {this.code, this.cause});

  final String message;
  final int? code;
  final Object? cause;

  @override
  String toString() =>
      'EfException(${code ?? '-'}): $message${cause != null ? ' ($cause)' : ''}';
}

class EfCryptoException extends EfException {
  EfCryptoException(super.message, {super.code, super.cause});
}

class EfAuthException extends EfException {
  EfAuthException(super.message, {super.code, super.cause});
}

class EfIoException extends EfException {
  EfIoException(super.message, {super.code, super.cause});
}

class EfPermissionException extends EfException {
  EfPermissionException(super.message, {super.cause});
}
