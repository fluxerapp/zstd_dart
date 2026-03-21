import 'dart:typed_data';

class ZstdException implements Exception {
  final String message;
  const ZstdException(this.message);

  @override
  String toString() => 'ZstdException: $message';
}

class ZstdCodec {
  static Uint8List compress(Uint8List input, {int level = 3}) {
    throw UnimplementedError();
  }

  static Uint8List decompress(Uint8List input) {
    throw UnimplementedError();
  }
}
